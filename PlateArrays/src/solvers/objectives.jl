



function margins(wells::BitMatrix)
    R,C=size(wells)
    rowsum=sum(wells[:,i] for i in 1:C)
    colsum=sum(wells[i,:] for i in 1:R)
    return rowsum,colsum
end 

function expected_LHS(platearray::PlateArray)
    P=sum(platearray.positives)
    N=sum(platearray.negatives)
    row_margin,col_margin=margins(platearray.wells)


    e_p_rows=P*row_margin/sum(row_margin)
    e_p_cols=P*col_margin/sum(col_margin)

    e_n_rows=N*row_margin/sum(row_margin)
    e_n_cols=N*col_margin/sum(col_margin)
    return e_p_rows,e_p_cols,e_n_rows,e_n_cols
end 


function LHS(platearray::PlateArray;kwargs...)
    expected_p_rows,expected_p_cols,expected_n_rows,expected_n_cols=expected_LHS(platearray)
    p_rows,p_cols=margins(platearray.positives)
    n_rows,n_cols=margins(platearray.negatives)
    pos_score= sum((p_rows.-expected_p_rows).^2) +sum((p_cols.-expected_p_cols).^2)
    neg_score= sum((n_rows.-expected_n_rows).^2) + sum((n_cols.-expected_n_cols).^2)

    return pos_score + neg_score 
end 




function neighbors(row::Int,col::Int,R::Int,C::Int)
    ringarray=Tuple{Int,Int}[]
    push!(ringarray,(max(row-1,1),col))
    push!(ringarray,(min(row+1,R),col))
    push!(ringarray,(row,min(col+1,C)))
    push!(ringarray,(row,max(col-1,1)))
    return ringarray

end
function neighboring_ring(row::Int,col::Int,ring::Int,R::Int,C::Int)
    wells=[(row,col)]
    sol=Tuple{Int,Int}[]
    sol=vcat(sol,wells)
    for i=1:ring
        rows=map(y -> y[1],wells)
        cols=map(y -> y[2],wells)
        wells=neighbors.(rows,cols,R,C)
        wells=reduce(vcat,wells)
        wells=unique(wells)
        sol=vcat(sol,wells)

    end
    return unique(sol)
end



function manhattan_distance(p1::Tuple{Int,Int},p2::Tuple{Int,Int})
    return sum(abs.(p1.-p2))
end 



function distance_score_ring(platearray::PlateArray)
    R,C=size(platearray.wells)
    pos_dist=zeros(Int,R,C)
    neg_dist=zeros(Int,R,C)
    

    M=max(R,C)

    for r in 1:R
        for c in 1:C
            if !platearray.wells[r,c]
                continue 
            else 
                for ring in 0:M
                    idxs=CartesianIndex.(neighboring_ring(r,c,ring,R,C))
                    foundpos=any(platearray.positives[idxs])
                    foundneg=any(platearray.negatives[idxs])
                    if foundpos && foundneg 
                        break 
                    else
                        if !foundpos 
                            pos_dist[r,c]+=1
                        end 
                        if !foundneg
                            neg_dist[r,c]+=1
                        end 
                    end 
                end 
            end 
        end 
    end 

    return sum(pos_dist .+ neg_dist)
end 



function distance_score_brute(platearray::PlateArray;distance=manhattan_distance,kwargs...)
    R,C=size(platearray.wells)
    pos_dist=zeros(Int,R,C)
    neg_dist=zeros(Int,R,C)
    
    pos_coords=Tuple.(findall(x->x==true,platearray.positives))
    neg_coords=Tuple.(findall(x->x==true,platearray.negatives))
    if length(pos_coords)==0
        pos_dist .= max(R,C)*platearray.wells
    else
        for r in 1:R 
            for c in 1:C
                if !platearray.wells[r,c]
                    continue 
                else 
                    pos_dist[r,c] = minimum(distance.(((r,c),), pos_coords ))

                end 
            end 
        end
    end 
    
    if length(neg_coords)==0
        neg_dist.=max(R,C)*platearray.wells
    else


        for r in 1:R 
            for c in 1:C
                if !platearray.wells[r,c]
                    continue 
                else 

                    neg_dist[r,c]= minimum(distance.(((r,c),), neg_coords ))
                end 
            end 
        end
    end 
    return sum(pos_dist .+ neg_dist)
end 







function minimax(platearray::PlateArray;kwargs...)
        return distance_score_brute(platearray;kwargs...)
end 

function scale(num::Real,lb::Real,ub::Real)

    return (num-lb)/(ub-lb)
end 


function hybrid(platearray::PlateArray;lambda=0.5,lb_dist=0,ub_dist=1,lb_LHS=0,ub_LHS=1,kwargs...)

    0<=lambda<=1 ? nothing : error("lambda must be between 0 and 1 inclusive.")
    s1=scale(minimax(platearray;kwargs...),lb_dist,ub_dist)
    s2=scale(LHS(platearray),lb_LHS,ub_LHS)

    score=lambda*s1 + (1-lambda)*s2
    return score 
end 



