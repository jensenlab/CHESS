"""
    sanitize_tokens(xs::AbstractVector{<:AbstractString};
                    lowercase::Bool=true,
                    replace_space_hyphen::Bool=true,
                    allow_digits::Bool=true,
                    keep_underscores::Bool=true,
                    drop_empty::Bool=true,
                    de_duplicate::Bool=true,
                    sort_items::Bool=false) -> Vector{String}

Sanitize a vector of strings for directory-safe usage.

Rules (in order):
1. `strip`
2. (optional) `lowercase`
3. (optional) replace whitespace and `-` with `_`
4. remove disallowed characters (keeps only `[a-z]`, optionally digits and `_`)
5. collapse consecutive `_`
6. trim leading/trailing `_`
7. (optional) drop empty strings
8. (optional) de-duplicate (stable)

# Examples
```julia
adverbs_s = sanitize_tokens(adverbs)
verbs_s   = sanitize_tokens(verbs)

# directory-safe pairings
names = random_adverb_verb_pairs(adverbs_s, verbs_s, 50)
"""
function sanitize_tokens(xs::AbstractVector{<:AbstractString};lowercase::Bool=true,replace_space_hyphen::Bool=true,allow_digits::Bool=true,keep_underscores::Bool=true,drop_empty::Bool=true,de_duplicate::Bool=true,sort_items::Bool=false)::Vector{String}
# Build allowlist regex dynamically
allowed = String["a-z"]
allow_digits      && push!(allowed, "0-9")
keep_underscores  && push!(allowed, "_")
allow_re = Regex("[^$(join(allowed))]")

function sanitize_one(s::AbstractString)::String
    x = strip(String(s))
    lowercase && (x = Base.lowercase(x))
    if replace_space_hyphen
        x = replace(x, r"[\s\-]+" => "_")
    end
    x = replace(x, allow_re => "")
    x = replace(x, r"_+" => "_")
    x = replace(x, r"^_+|_+$" => "")
    return x
end

out = String[]
for s in xs
    y = sanitize_one(s)
    if !drop_empty || !isempty(y)
        push!(out, y)
    end
end


sort_items && sort!(out)
de_duplicate && unique!(out)
return out
end


const adverbs = sanitize_tokens(String[
    "abackly","abashedly","aberrantly","abidingly","abiogenically","abjectly","ablatively","ably",
    "abnormally","abolitionistically","abominably","aborally","abrasively","abruptly","absently",
    "absentmindedly","absolutely","absolvably","absorbingly","abstemiously","abstractedly",
    "abstractly","absurdly","abundantly","abusively","academically","acceleratively","accentually",
    "acceptably","acceptingly","accessibly","accidentally","accommodatingly","accompaniedly",
    "accordingly","accurately","accusingly","accustomably","acidly","acoustically","acquisitively",
    "acrimoniously","actively","actually","acutely","adaptively","additively","adequately",
    "adhesively","adjectivally","administratively","admirably","admiringly","admissibly",
    "admittedly","admonishingly","adorably","adroitly","adulterously","advantageously",
    "adventitiously","adventurously","adversarially","adversatively","adversely","advisedly",
    "aerodynamically","aesthetically","affably","affectingly","affectionately","affirmatively",
    "affirmingly","affluently","affordably","aforementionedly","afreshly","afterwardly","agelessly",
    "aggravatingly","aggressively","agilely","agonizingly","agreeably","agreeingly","agriculturally",
    "aimlessly","airily","alarmingly","albeitly","alertly","alienably","alienatingly","allegedly",
    "allegorically","alliteratively","allocatively","allotropically","allusively","almightily",
    "aloneingly","alphabetically","altogetherly","altruistically","amazingly","ambiguously",
    "ambitiously","amiably","amicably","amorphously","amply","anachronistically","analogically",
    "analytically","anaphorically","anatomically","anciently","angelically","angrily","animally",
    "animatedly","anomalously","anonymously","antagonistically","antecedently","anthropologically",
    "anticipatorily","anticipatively","anxiously","apathetically","apodictically","apologetically",
    "apostolically","apparently","appealingly","appetizingly","applicably","appositely",
    "appreciably","appreciatively","apprehensively","approachably","appropriately","approximately",
    "aptly","arbitrarily","arcadianly","archaeologically","archaically","ardently","arguably",
    "argumentatively","arithmetically","armfully","aromatically","artfully","artistically",
    "ashamedly","asininefully","askingly","aspirationally","assaultively","assertedly",
    "assertively","assiduously","associatively","assumptively","assuredly","astonishingly",
    "astoundingly","astrally","astronomically","astutely","asymmetrically","atheistically",
    "athletically","atomically","atrociously","attentively","attitudinally","attractively",
    "attributively","audaciously","audibly","authoritatively","autobiographically","autocratically",
    "automatically","autonomously","avariciously","avowedly","awkwardly","axiomatically",
    "babyishly","badly","baggyingly","baldly","banally","barbarically","barely","basely",
    "basically","bashfully","bastardly","bathroomly","beastly","beautifully","beggarly",
    "begrudgingly","behaviorally","belatedly","belligerently","beneficially","benevolently",
    "benignly","bestially","bewilderedly","bewilderingly","biasly","bibliographically",
    "bicamerally","biennially","bigly","bilaterally","biochemically","biographically","biologically",
    "bipolarly","bitterly","blamelessly","blandly","blankly","blatantly","bleakly","blindly",
    "blissfully","bloodily","bluntly","boastfully","boisterously","boldly","bombastically","bonily",
    "boorishly","borderliney","boringly","botanically","bounteously","boyishly","brashly","bravely",
    "brazenly","breadthwise-ly","briefly","brightly","brilliantly","briskly","broadly","brokenly",
    "brotherly","brutally","bubblingly","buoyantly","bureaucratically","burstingly","busily",
    "calamitously","calculatedly","calmly","calorically","candidly","canonically","capably",
    "capitally","capriciously","carefully","carelessly","caressingly","carnally","cartoonishly","categorically",
    "causally","cautiously","ceaselessly","celestially","centrally","ceremonially","certainly",
    "chaotically","characteristically","charitably","charmingly","chastely","cheaply","cheerfully",
    "chemically","chestily","chiefly","childishly","chilly","chirpily","chivalrously","chronically",
    "chronologically","circuitously","circularly","civically","civilly","classically","cleanly",
    "clearly","clerkly","cleverly","clinically","closely","clumsily","coarsely","coaxingly",
    "coherently","coincidentally","coldly","collectively","colloquially","colorfully","comfortably",
    "comfortingly","comically","commandingly","commendably","commercially","commonly","communally",
    "comparably","comparatively","compassionately","compatibly","competently","competitively",
    "complacently","complainingly","completely","complexly","compliantly","compulsively",
    "computationally","conceivably","concentrically","conceptually","concisely","conclusively",
    "concretely","conditionally","confessedly","confidently","confidentially","conformably",
    "confoundedly","confusingly","congenially","congruently","conjecturally","conjointly",
    "consciously","consecutively","consensually","consequently","conservatively","considerably",
    "considerately","consistently","conspicuously","constantly","constitutionally","constrainedly",
    "constructively","consumptively","contagiously","contemporaneously","contemptibly",
    "contemptuously","contentedly","contextually","continually","continuously","contractually",
    "contradictorily","contrariwise-ly","contrarily","contrastingly","contributively",
    "controversially","conveniently","conventionally","conversationally","convincingly",
    "convivially","coolly","cooperatively","coordinately","cordially","correctly","correspondingly",
    "corruptly","cosmically","costly","courageously","courteously","covertly","craftily","crassly",
    "crazily","creakily","creatively","credibly","creditably","credulously","criminally","crisply",
    "critically","crookedly","crossly","cruelly","cryptically","culturally","cunningly","curiously",
    "currently","cursorily","curtly","customarily","cutely","cynically","daily","daintily",
    "damnably","dangerously","daringly","darkly","dartingly","dastardly","dauntingly",
    "deafeningly","dearly","deceitfully","decently","deceptively","decidedly","decisively",
    "decoratively","deeply","defectively","defensively","deferentially","defiantly","definitely",
    "deftly","dejectedly","deliberately","delicately","delightfully","delightingly","deliriously",
    "delusively","democratically","demonstrably","demonstratively","demurely","dependably",
    "deservedly","descriptively","desperately","despicably","despitefully","despondently",
    "destructively","detachedly","detailingly","detectably","determinately","deterministically",
    "determinedly","devastatingly","deviously","devotedly","devoutly","dexterously","diabolically",
    "diagnostically","dialectically","diametrically","digitally","diligently","dimly","directly",
    "disadvantageously","disagreeably","disastrously","discernibly","discernibly",
    "disciplinarily","discreetly","discretely","disdainfully","disgustedly","disgustingly",
    "dishonestly","disjointedly","disloyally","dismally","disorderly","disparagingly",
    "dispassionately","displeasingly","disproportionately","disputably","disquietingly",
    "disrespectfully","distantly","distinctively","distinctly","distractingly","disturbingly",
    "diversely","divinely","docilely","doggedly","dolorously","domestically","dominantly",
    "doubtfully","doubtlessly","downrightly","dramatically","drearily","drily","drippingly",
    "drunkenly","dryly","dually","dully","duly","dumbly","dynamically","eagerly","early",
    "earnestly","earthly","easily","eccentrically","ecclesiastically","economically","ecstatically",
    "edgewise-ly","educationally","eerily","effectively","efficiently","effortlessly","egregiously",
    "elaborately","elastically","electronically","elegantly","elementarily","elliptically",
    "eloquently","elsewhere-ly","embarrassedly","embarrassingly","eminently","emotionally",
    "empathetically","emphatically","empirically","encouragingly","endlessly","energetically",
    "engagingly","enigmatically","enormously","enoughly","enragedly","enrichingly","entirely",
    "entreatingly","environmentally","equally","equanimously","equationally","equitably",
    "erratically","essentially","esthetically","eternally","ethically","ethnically","euphemistically",
    "evaluatively","evenly","eventually","evidently","evilly","evolutionarily","exactly",
    "exasperatingly","exceedingly","excellently","exceptionally","excitedly","exclusively",
    "excruciatingly","exhaustively","exhilaratingly","exorbitantly","expansively","expectantly",
    "expediently","expensively","experimentally","expertly","explicitly","explosively",
    "exponentially","expressively","exquisitely","externally","extraordinarily","extremely",
    "factually","faintly","faithfully","fallibly","familiarly","famously","fancifully",
    "fantastically","far-reachingly","farcically","fashionably","fastidiously","fatally",
    "faultlessly","favorably","fearfully","fearlessly","feasibly","federally","feebly","fervently",
    "fervidly","festively","feverishly","fiercely","figuratively","finally","financially","finely",
    "finitely","firmly","firstly","fiscally","fitfully","fixedly","flagrantly","flamboyantly",
    "flatly","flawlessly","fleetingly","flexibly","flimsily","flippantly","fluently","fluidly",
    "fondly","foolishly","forcefully","forcibly","formally","formidably","forthrightly",
    "fortunately","forwardly","frankly","frantically","freely","frenetically","frequently",
    "freshly","friendly","frightfully","frigidly","friskily","frivolously","frontally","frostily",
    "frugally","fruitfully","fully","fundamentally","furiously","furtherly","futilely","gainfully",
    "gallantly","garishly","generally","generically","generously","genetically","gently",
    "genuinely","geographically","geologically","geometrically","giddily","gigantically","gladly",
    "glamorously","gleefully","globally","gloomily","gloriously","glossily","godly","gracefully",
    "graciously","gradually","grammatically","grandly","gratefully","gratuitously","gravely",
    "greatly","greedily","grimly","grossly","grotesquely","grudgingly","guardedly","guiltily",
    "habitually","haphazardly","happily","hardily","hardly","harmfully","harmlessly","harmoniously",
    "harshly","hastily","haughtily","healthily","heartily","heedlessly","helpfully","helplessly",
    "henceforthly","heroically","hesitantly","highly","hilariously","historically","honestly",
    "honorably","hopefully","horribly","hospitably","hourly","humbly","humidly","humorlessly",
    "hungrily","hurriedly","hurtfully","hypothetically","hysterically","ideally","identically",
    "ideologically","idiotically","idly","illegally","illegibly","illicitly","illogically",
    "illuminatingly","illusorily","imaginatively","immaculately","immanently","immaterially",
    "immensely","imminently","immoderately","immorally","impartially","impatiently","impeccably",
    "impersonally","impertinently","imperviously","impetuously","implausibly","implicitly",
    "imploringly","impolitely","importantly","impossibly","imprecisely","impressively","improperly",
    "impulsively","inaccurately","inadequately","inadvertently","inalienably","incomparably",
    "incompletely","inconclusively","incongruently","inconsistently","inconspicuously","incorrectly",
    "increasingly","incredibly","indecently","indeedly","indefinitely","independently",
    "indescribably","indifferently","indirectly","indisputably","indistinctly","individually",
    "indolently","indubitably","inevitably","inexcusably","inexorably","inexplicably","infamously","infectiously",
    "inferentially","infinitely","inflexibly","informally","infrequently","inherently","initially",
    "innately","innocently","innovatively","inordinately","inpatiently","inquisitively","insanely",
    "insatiably","insecurely","insensitively","insidiously","insincerely","insistently","instantly",
    "instinctively","institutionally","instructively","insufficiently","insultingly",
    "intellectually","intelligently","intensely","intentionally","interactively","interchangeably",
    "interestingly","interiorly","internally","internationally","interpretively","intermittently",
    "interpersonally","intimately","intolerably","intractably","intrinsically","intuitively",
    "invariably","inventively","inversely","invincibly","invisibly","invitingly","inwardly",
    "ironically","irrationally","irregularly","irrelevantly","irresponsibly","irrevocably",
    "irritably","irritatingly","isolatedly","jarringly","jealously","jestingly","jocosely",
    "jovially","joyfully","joylessly","judiciously","justly","keenly","kindly","kinetically",
    "knavishly","knowingly","lamentably","languidly","largely","lastingly","lately","laudably",
    "lavishly","lawfully","lazily","leisurely","lengthily","leniently","lesserly","lethally",
    "liberally","lightly","likely","limpingly","linearly","literally","lively","loftily","logically",
    "lonely","longingly","loosely","loudly","lovely","lovingly","loyally","luckily","ludicrously",
    "lushly","madly","magically","magnificently","mainly","maliciously","manfully","marginally",
    "marvelously","massively","masterfully","materially","maternally","maturely","meaningfully",
    "mechanically","medically","meekly","melancholically","melodically","memorably","mentally",
    "mercifully","merely","merrily","methodically","meticulously","mightily","mildly","mindfully",
    "mindlessly","minimally","ministerially","miraculously","miserably","misleadingly","moderately",
    "modestly","momentarily","monetarily","monotonously","monthly","morally","mortally","mostly",
    "motherly","motionlessly","motivationally","movingly","multiply","mundanely","musically",
    "mutually","mysteriously","naively","namely","narrowly","nationally","naturally","nearly",
    "neatly","necessarily","needlessly","nervously","neutrally","newly","nicely","nightly","nimbly",
    "nobly","noisily","nominally","normally","notably","noticeably","notoriously","novelly",
    "numerically","objectively","obligingly","obliquely","obnoxiously","obscenely","obscurely",
    "observably","observantly","obsessively","obstinately","occasionally","oddly","offensively",
    "officially","ominously","openly","operationally","opinionatedly","opportunely",
    "opportunistically","optimally","optimistically","optionally","orally","orderly","ordinarily",
    "organizationally","originally","orthogonally","ostensibly","outlandishly","outwardly","overly",
    "painfully","painlessly","painstakingly","palatably","paleontologically","palpably","panically",
    "paradoxically","parallelly","parentally","partially","particularly","passably","passionately",
    "passively","pastorally","patiently","peacefully","peculiarly","pedantically","peevishly",
    "penally","perceptibly","perceptively","perfectly","perfidiously","perhapsly","perilously",
    "permanently","permissibly","persistently","personally","persuasively","pertinently",
    "pervasively","pessimistically","philosophically","physically","pictorially","plainly",
    "plausibly","playfully","pleasantly","pleasingly","plentifully","poetically","pointedly",
    "politely","politically","poorly","popularly","portly","positively","possibly","powerfully",
    "practically","pragmatically","precisely","predictably","preferably","prematurely","presently",
    "presumably","presumptuously","prettily","previously","primarily","primitively","privately",
    "probably","problematically","profoundly","progressively","prominently","promptly","properly",
    "proportionally","prospectively","protectively","proudly","provably","providentially",
    "provincially","prudently","psychologically","publicly","punctually","purely","purposefully",
    "quaintly","qualitatively","quantitatively","quarterly","queasily","quickly","quietly",
    "quintessentially","rabidly","racially","radically","randomly","rapidly","rarely","rationally",
    "readily","really","reasonably","recklessly","recognizably","recurrently","redundantly",
    "reflectively","regally","regardlessly","regularly","relatively","relentlessly","reliably",
    "reluctantly","remarkably","remotely","repeatedly","reportedly","reproachfully","reputedly",
    "resentfully","resolutely","respectfully","respectively","responsibly","restlessly",
    "restrictively","retailly","rhetorically","richly","ridiculously","rightly","rigidly","ripely",
    "ritually","robustly","roughly","roundly","routinely","royally","rudely","ruthlessly","sadly",
    "safely","saltly","sanely","sarcastically","savagely","scarcely","scarily","scientifically",
    "scornfully","scrupulously","securely","sedately","seemingly","selectively","selfishly",
    "sensibly","sensitively","separately","serially","seriously","severely","shabbily","shakily",
    "shamefully","sharply","sheepishly","shiftily","shoddily","shortly","shrewdly","shrilly",
    "shyly","sickly","significantly","silently","similarly","simply","sincerely","sinfully",
    "singularly","skeptically","skillfully","slightly","smoothly","socially","softly","solely",
    "solemnly","solidly","sometimesly","soonly","sorrowfully","soundly","sourly","spatially",
    "specially","specifically","spectacularly","speedily","spiritually","splendidly","sporadically",
    "squarely","stably","steadily","stealthily","sternly","stillly","strangely","strategically",
    "strictly","stridently","strongly","structurally","stubbornly","studiously","stunningly",
    "subconsciously","subjectively","sublimely","subsequently","substantially","subtly",
    "successfully","succinctly","suddenly","sufficiently","suitably","superficially","superiorly",
    "supremely","surely","suspiciously","sweetly","swiftly","symbolically","symmetrically",
    "sympathetically","systematically","tacitly","tactfully","tactically","talkatively","tardily",
    "tastefully","taxonomically","tearfully","technically","temperamentally","temporarily",
    "tenderly","terminally","terribly","thankfully","theatrically","thematically","theologically",
    "theoretically","thinly","thoroughly","thoughtfully","thoughtlessly","tightly","timely",
    "tirelessly","tolerably","tolerantly","tonally","totally","tragically","tranquilly",
    "transparently","tremendously","truly","trustfully","truthfully","typically","ultimately",
    "unabashedly","unacceptably","unaccountably","unambiguously","unapologetically","unavoidably",
    "unbearably","unbelievably","unbiasedly","unconditionally","unconsciously","uncontrollably",
    "undeniably","underhandedly","understandably","undoubtedly","uneasily","unequally","unerringly",
    "unexpectedly","unfairly","unfaithfully","unfathomably","unfavorably","unfortunately",
    "unhappily","uniformly","unimpressively","unjustly","unkindly","unlawfully","unluckily",
    "unmistakably","unnaturally","unnecessarily","unofficially","unpleasantly","unpredictably",
    "unquestionably","unreasonably","unreliably","unreservedly","unsafely","unsuccessfully",
    "unsurprisingly","unswervingly","untimely","untruthfully","unusually","unwillingly","upwardly",
    "urbanely","urgently","usefully","uselessly","usually","utterly","vaguely","vainly","valiantly",
    "validly","variably","variously","vastly","vehemently","verbally","vertically","vicariously",
    "viciously","victoriously","vigorously","violently","visibly","vitally","vocally",
    "voluntarily","warmly","weakly","wealthily","wearily","weekly","weirdly","wellly","wholly",
    "widely","wildly","willingly","wisely","wistfully","wonderfully","worldly","worriedly",
    "wrongly","wryly","yearly","youthfully","zealously",
])

const verbs = sanitize_tokens(String[
    "accepting","achieving","acquiring","acting","adapting","adding","adjusting","admiring",
    "admitting","adopting","advising","affording","agreeing","alerting","allowing","altering",
    "amazing","amusing","analyzing","answering","anticipating","apologizing","appearing",
    "applying","appointing","appreciating","approving","arguing","arranging","arriving","asking",
    "assessing","assigning","assisting","assuming","assuring","attaching","attacking","attempting",
    "attending","attracting","auditing","authorizing","avoiding","awaking","baking","balancing",
    "banning","bandaging","banging","bartering","bathing","battling","being","bearing","beating",
    "becoming","begging","beginning","behaving","believing","belonging","bending","benefiting",
    "betting","bidding","binding","biting","bleeding","blessing","blinking","blocking","blowing",
    "boiling","bolting","bombing","booking","boring","borrowing","bouncing","bowing","breaking",
    "breathing","breeding","bringing","broadcasting","brushing","building","burning","bursting",
    "buying","calculating","calling","camping","canceling","capturing","caring","carrying","carving",
    "catching","causing","celebrating","challenging","changing","charging","chasing","chatting",
    "checking","cheering","chewing","choosing","chopping","claiming","cleaning","clearing",
    "climbing","clinging","closing","coaching","collecting","coloring","coming","commanding",
    "commenting","committing","comparing","competing","complaining","completing","composing",
    "computing","concentrating","concluding","conducting","confirming","connecting","considering",
    "consisting","consulting","containing","continuing","controlling","converting","cooking",
    "copying","correcting","costing","counting","covering","cracking","crafting","crashing",
    "crawling","creating","crediting","creeping","critiquing","crossing","crushing","crying",
    "cultivating","curing","curling","cutting","cycling","dancing","daring","dealing","deciding",
    "declaring","declining","decoding","defending","defining","delaying","delegating","delivering",
    "demanding","demonstrating","denying","depending","describing","designing","desiring",
    "destroying","detailing","detecting","determining","developing","devoting","diagnosing",
    "dictating","dying","differing","digging","directing","disagreeing","disappearing",
    "discovering","discussing","disliking","displaying","distributing","diving","dividing","doing",
    "donating","downloading","dragging","drawing","dreaming","dressing","drinking","driving",
    "dropping","drying","dumping","earning","eating","editing","educating","electing","emailing",
    "emerging","employing","enabling","encouraging","ending","enforcing","engineering","enjoying",
    "enrolling","ensuring","entering","equaling","equipping","escaping","establishing","estimating",
    "evaluating","examining","exceeding","exchanging","excusing","executing","exercising","existing",
    "expanding","expecting","explaining","exploring","exporting","exposing","extending","facing",
    "failing","falling","fastening","fearing","feeding","feeling","fighting","filing","filling",
    "filming","finding","finishing","fitting","fixing","flagging","fleeing","floating","flooding",
    "flowing","flying","focusing","folding","following","forbidding","forcing","forecasting",
    "forgetting","forgiving","forming","fostering","founding","framing","freeing","freezing",
    "frightening","functioning","funding","gaining","gathering","generating","getting","giving",
    "glancing","glowing","going","governing","grabbing","graduating","granting","grasping",
    "greeting","grinding","growing","guessing","guiding","handling","hanging","happening","harming",
    "hating","having","healing","hearing","helping","hiding","hiring","hitting","holding","hoping",
    "hosting","hugging","hunting","hurrying","hurting","identifying","ignoring","illustrating",
    "imagining","implementing","implying","importing","impressing","improving","including",
    "increasing","indicating","influencing","informing","inheriting","initiating","injuring",
    "innovating","inputting","inspecting","inspiring","installing","intending","interacting",
    "interesting","interpreting","interrupting","introducing","inventing","investing","inviting",
    "involving","ironing","joining","judging","jumping","justifying","keeping","kicking","killing",
    "kissing","kneeling","knitting","knocking","knowing","labeling","landing","lasting","laughing",
    "launching","learning","leaving","lending","letting","lifting","liking","limiting","listening",
    "living","loading","locating","locking","logging","looking","losing","loving","maintaining",
    "making","managing","mattering","meaning","measuring","meeting","melting","mentioning",
    "mentoring","merging","migrating","minding","missing","mixing","modeling","monitoring","moving",
    "multiplying","naming","navigating","needing","negotiating","noticing","obeying","objecting",
    "observing","obtaining","occurring","offering","opening","operating","opposing","ordering",
    "organizing","overcoming","owing","owning","packing","painting","passing","paying","performing",
    "permitting","phoning","picking","planning","playing","pleasing","plugging","pointing",
    "polishing","popping","posing","possessing","posting","practicing","predicting","preferring",
    "preparing","presenting","preserving","pressing","pretending","preventing","printing",
    "proceeding","processing","producing","programming","progressing","promising","promoting",
    "proposing","protecting","proving","providing","publishing","pulling","punching","pushing",
    "putting","qualifying","questioning","quitting","racing","raining","raising","reaching",
    "reading","realizing","receiving","recognizing","recommending","recording","recovering",
    "reducing","referring","reflecting","refusing","registering","regretting","rejecting",
    "relating","relaxing","releasing","relying","remaining","remembering","reminding","removing",
    "repairing","repeating","replacing","replying","reporting","representing","requesting",
    "requiring","rescuing","researching","resolving","respecting","responding","resting",
    "restoring","restricting","resulting","retiring","returning","revealing","reviewing","revising",
    "ringing","rising","risking","rolling","running","saving","saying","scheduling","scoring",
    "searching","seeing","seeking","selecting","selling","sending","separating","serving","setting",
    "settling","sewing","shaking","sharing","shining","shipping","shooting","shopping","shouting",
    "showing","shutting","singing","sinking","sitting","skating","sleeping","sliding","slipping",
    "smiling","smoking","snapping","solving","sorting","sounding","speaking","spending","spinning",
    "splitting","spoiling","spreading","springing","standing","starting","stating","staying",
    "stealing","stepping","sticking","stopping","storing","storming","stretching","striking",
    "studying","submitting","succeeding","suffering","suggesting","supplying","supporting",
    "supposing","surprising","surviving","swallowing","swimming","switching","taking","talking",
    "teaching","telling","tending","testing","thanking","thinking","throwing","tidying","tying",
    "touching","traveling","treating","trying","turning","typing","understanding","undoing",
    "uniting","updating","upgrading","using","validating","valuing","varying","viewing","visiting",
    "voting","waiting","walking","wanting","warning","watching","wearing","winning","wiping",
    "wishing","wondering","working","worrying","writing","yielding","zipping","zooming",
])




"""
    random_adverb_verb_pairs(adverbs, verbs, n; rng=Random.default_rng(), unique=true) -> Vector{String}

Generate `n` directory-safe random strings of the form `adverb_verb` by sampling
from `adverbs` and `verbs` (assumed to be Julia vectors of strings).

Directory-safety rules applied:
- lowercase
- spaces and hyphens become `_`
- all other non `[a-z0-9_]` characters removed
- repeated `_` collapsed; leading/trailing `_` stripped

If `unique=true`, results are unique; throws if `n` exceeds the number of possible
unique combinations after sanitization.
"""
function random_adverb_verb_pairs(n::Integer=1;
                                  adverbs=adverbs,
                                  verbs = verbs,
                                  rng::AbstractRNG = Random.default_rng(),
                                  make_unique::Bool = true)::Vector{String}


    if make_unique
        # Upper bound on unique pairings (after sanitization)
        maxuniq = length(unique(adverbs)) * length(unique(verbs))
        n > maxuniq && throw(ArgumentError("Requested n=$n unique pairs, but only $maxuniq possible."))

        out = Set{String}()
        while length(out) < n
            a = rand(rng, adverbs)
            v = rand(rng, verbs)
            push!(out, string(a, "_", v))
        end
        return collect(out)
    else
        out = Vector{String}(undef, n)
        @inbounds for i in 1:n
            out[i] = string(rand(rng, adverbs), "_", rand(rng, verbs))
        end
        return out
    end
end
