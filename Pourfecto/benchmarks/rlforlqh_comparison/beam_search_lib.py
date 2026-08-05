"""Standalone port of the `Machine` class from
../../../rlforlqh/Beam Search/beam_search.ipynb (cell 2), so it can be driven programmatically
across a size/seed sweep instead of only from inside the notebook.

The search logic (BeamSearch/beam_search/transition_func/e1/simulate_cmd/is_goal_status) is
unmodified from the notebook. Two additions, both clearly marked below:

  1. An optional wall-clock `deadline` in `beam_search`'s main loop. The original has no time bound
     beyond a 100-iteration cap; at the larger grid sizes this benchmark sweeps to (up to 20x20),
     each iteration's candidate generation is O(n^2) per beam and can run long. Without a deadline a
     single hard instance could stall the whole sweep.
  2. `BeamSearch` accepts a `goal` dict that must have an entry for *every* grid cell, not only
     cells where the plate needs to hold something. This is required to make the success criterion
     match greedy.py and Pourfecto: `is_goal_status` only checks cells present as keys in `goal`, so
     if a cell is silently omitted (as the notebook's own `set_tasks` does for any cell absent from
     the input text file) beam search is free to leave leftover content there and still call it
     solved. run_beam_search.py builds `goal` with a zero-array entry for every column up front so
     "solved" means the same thing -- exact full-grid match -- for every solver in this benchmark.
"""
import copy
import math
import time
from collections import defaultdict

import numpy as np


def default_value():
    return np.array([0, 0])


class Machine:
    def __init__(self):
        pass

    def BeamSearch(self, start, goal, beam_size=3, N=5, head_pos=(0, 0), tip_cap=100,
                    well_cap=500, num_sol=2, deadline=None):
        self.N = N
        self.head_pos = head_pos
        self.tip_cap = tip_cap
        self.well_cap = well_cap
        self.num_sol = num_sol

        head = np.zeros((self.num_sol, 1))
        self.status = np.hstack((start, head))
        self.goal = copy.deepcopy(goal)

        s = time.time()
        self.solutions = self.beam_search(self.status, beam_size, deadline=deadline)
        t = time.time()
        self.timing = t - s

    class Beam:
        def __init__(self, score, cost, status, head_pos, protocol, visit_times):
            self.score = copy.deepcopy(score)
            self.cost = cost
            self.status = status
            self.head_pos = head_pos
            self.protocol = protocol
            self.visit_times = copy.deepcopy(visit_times)
            self.manipulated = self.unique_wells_manipulated()

        def unique_wells_manipulated(self):
            manipulated = []
            for col in self.visit_times.keys():
                if self.visit_times[col] > 0:
                    manipulated.append(col)
            return manipulated

    def beam_search(self, curr_status, beam_size, mc=1, ac=0, dc=0, zc=0, deadline=None):
        self.mc = mc
        self.ac = ac
        self.dc = dc
        self.zc = zc
        status = copy.deepcopy(curr_status)

        init_beam = self.Beam([], 0, status, self.head_pos, [], defaultdict(int))
        beams = [init_beam]
        solutions = []
        iter_num = 0

        while len(solutions) < beam_size and iter_num < 100:
            if deadline is not None and time.time() > deadline:  # addition (see module docstring)
                break

            new_beams = []
            for beam in beams:
                candidates = self.transition_func(beam, beam_size)
                new_beams.extend(candidates)

            if len(new_beams) == 0:
                break

            score_Arr = [new_beam.score for new_beam in new_beams]
            norms = np.linalg.norm(score_Arr, axis=0)
            norms[norms == 0] = 1  # guard: original divides by zero-norm columns when every
            # candidate ties at 0 on some score component (e.g. num_ops*unique_manipulated at
            # iteration 0), which is silent under numpy's default warn-only float division.
            score_Arr = score_Arr / norms

            for i, new_beam in enumerate(new_beams):
                new_beam.score = score_Arr[i, :]

            new_beams = sorted(new_beams, key=lambda x: x.score[0] + x.score[1] + 0.1 * x.score[2] + 0.1 * x.score[3])
            k = min(beam_size, len(new_beams))
            new_beams = new_beams[:k]

            beams = []
            for beam in new_beams:
                if self.is_goal_status(beam):
                    solutions.append(beam)
                else:
                    beams.append(beam)

            if len(beams) == 0 and len(solutions) < beam_size:
                return solutions
            iter_num += 1
        return solutions

    def transition_func(self, beam, beam_size):
        candidates = []
        head_vol = np.sum(beam.status[:, -1])
        head_C = beam.status[:, -1] / head_vol if head_vol > 0 else beam.status[:, -1]

        for i in range(beam.status.shape[1] - 1):
            well_vol = np.sum(beam.status[:, i])
            well_C = beam.status[:, i] / well_vol if well_vol > 0 else beam.status[:, i]

            if i in self.goal.keys():
                goal_vol = np.sum(self.goal[i])
                goal_C = self.goal[i] / goal_vol if goal_vol > 0 else self.goal[i]

                cmd = None
                if np.any(well_C != goal_C):
                    if well_vol == 0:
                        if head_vol > 0 and np.all(head_C == goal_C):
                            cmd = (2, i, min(head_vol, goal_vol))
                    else:
                        cmd = (1, i, min(well_vol, self.tip_cap - head_vol))
                else:
                    if well_vol > goal_vol:
                        cmd = (1, i, min(well_vol - goal_vol, self.tip_cap - head_vol))
                    else:
                        if head_vol > 0 and np.all(head_C == goal_C):
                            cmd = (2, i, min(goal_vol - well_vol, head_vol))

                if cmd is not None:
                    beam_cand = self.beam_after_cmd(cmd, beam, i)
                    candidates.append(beam_cand)
            else:
                if well_vol == 0:
                    if head_vol > 0:
                        cmd = (0, i, head_vol)
                        candidates.append(self.beam_after_cmd(cmd, beam, i))
                        cmd = (2, i, min(self.well_cap, head_vol))
                        candidates.append(self.beam_after_cmd(cmd, beam, i))
                else:
                    if head_vol > 0:
                        if np.all(head_C == well_C):
                            cmd = (2, i, min(self.well_cap - well_vol, head_vol))
                            candidates.append(self.beam_after_cmd(cmd, beam, i))
                            if head_vol < self.well_cap - well_vol:
                                cmd = (0, i, head_vol)
                                candidates.append(self.beam_after_cmd(cmd, beam, i))
                    cmd = (1, i, min(well_vol, self.tip_cap))
                    candidates.append(self.beam_after_cmd(cmd, beam, i))

        return candidates

    def e1(self, beam):
        C_diff = 0
        rmsd = 0
        for col, sol in self.goal.items():
            goal_vol = np.sum(self.goal[col])
            goal_C = self.goal[col] / goal_vol if goal_vol > 0 else self.goal[col]
            well_vol = np.sum(beam.status[:, col])
            well_C = 0
            if well_vol != 0:
                well_C = beam.status[:, col] / well_vol
            C_diff += np.sum(abs(well_C - goal_C))
            rmsd += abs(well_vol - goal_vol)
        rmsd = math.sqrt(rmsd / len(self.goal.keys()))
        unique_manipulated = len(beam.manipulated)
        num_ops = sum(beam.visit_times.values())

        score = np.array([C_diff, rmsd, num_ops * unique_manipulated, beam.cost])
        beam.score = score

    def beam_after_cmd(self, cmd, beam, col):
        next_cost, next_status, next_head_pos = self.simulate_cmd(cmd, beam.head_pos, beam.status)
        next_protocol = copy.deepcopy(beam.protocol)
        next_protocol.append(cmd)
        new_visit_times = copy.deepcopy(beam.visit_times)
        new_visit_times[col] += 1

        beam_cand = self.Beam([], beam.cost + next_cost, next_status, next_head_pos, next_protocol, new_visit_times)
        self.e1(beam_cand)
        return beam_cand

    def simulate_cmd(self, command, head_pos, status):
        cost = 0
        op, col, vol = command
        next_status = copy.deepcopy(status)

        x, y = col // self.N, col % self.N
        next_head_pos = (x, y)

        move_dst = abs(x - head_pos[0]) + abs(y - head_pos[1])
        cost += move_dst * self.mc
        if op == 0:
            cost += self.zc
            next_status[:, -1] = 0
        elif op == 1:
            cost += self.ac
            C = status[:, col] / np.sum(status[:, col])
            vol = vol * C
            next_status[:, col] -= vol
            next_status[:, -1] += vol
        elif op == 2:
            cost += self.dc
            C = status[:, -1] / np.sum(status[:, -1])
            vol = vol * C
            next_status[:, col] += vol
            next_status[:, -1] -= vol
        else:
            raise ValueError(f"operation {op} is not recognized")

        return cost, next_status, next_head_pos

    def is_goal_status(self, beam):
        return beam.score[0] == 0 and beam.score[1] == 0
