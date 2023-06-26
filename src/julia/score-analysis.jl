using JSON, CSV, DataFrames, DataFramesMeta
using ColorSchemes, ColorBrewer
using CairoMakie

run = JSON.parsefile("data/LSC23.json")
scores = CSV.read("data/scores-LSC23.csv", DataFrame)

team_id_to_name = Dict(map(x -> x["uid"]["string"] => x["name"], run["description"]["teams"]))
tasks = filter(x -> length(x["submissions"]) > 0, run["tasks"])

countdown_offset = 5000 #subtract the 5 second init/countdown period from the task start to be consistent with analysis performed in other sections

submissions = DataFrame[]

for t in tasks

    task_name = t["description"]["name"]
    task_group = t["description"]["taskGroup"]["name"]
    task_start = t["started"] + countdown_offset

    for s in t["submissions"]
        push!(submissions, DataFrame(
            task = task_name,
            group = task_group,
            time = s["timestamp"] - task_start,
            team = team_id_to_name[s["teamId"]["string"]],
            member = s["memberId"]["string"],
            item = haskey(s, "item") ? s["item"]["name"] : "",
            text = haskey(s, "text") ? s["text"] : "",
            status = s["status"]
        ))
    end

end

submissions = vcat(submissions...)

submissions[!, :group] = replace.(submissions[:, :group], "LSC-" => "")

task_type_count = length(unique(submissions[:, :group]))
team_count = length(team_id_to_name)

## total scores
score_sum = combine(groupby(scores, [:team, :group]), :score => sum)


g = groupby(score_sum, :group)
foreach(x -> x[:, :score_sum] = 1000 * x[:, :score_sum] ./ maximum(x[:, :score_sum]), g)
score_sum_normalized = combine(g, :)

sort!(score_sum_normalized, :group)

oder = sort(combine(groupby(score_sum_normalized, :team), :score_sum => sum => :sum), :sum, rev = true)[:, :team]

score_sum_normalized = @rorderby score_sum_normalized findfirst(==(:team), oder)

pos = collect(Iterators.flatten(([[i, i, i, i, i, i] for i in 1:team_count])))
grp = collect(Iterators.flatten(([[1, 2, 3, 4, 5, 6] for i in 1:team_count])))
team_names = unique(score_sum_normalized[:, :team])

colors = palette("Paired", task_type_count)

fig = Figure()

ax = Axis(fig[1, 1],
xlabel = "Team",
ylabel = "Score",
xticks = (1:team_count, team_names),
yticks = 0:500:(1000*task_type_count),
xticklabelrotation = pi/4,
title = "")

barplot!(
    pos, score_sum_normalized[:, :score_sum],
    stack = grp,
    color = colors[grp]
)

labels = score_sum_normalized[1:task_type_count, :group]

Legend(fig[2,1], [PolyElement(polycolor = colors[i]) for i in 1:task_type_count], labels, "Task Type", orientation = :horizontal, framevisible = false, nbanks = 2)

save("plots/score_sum.pdf", fig)



## correct/wrong submissions per team

#count only one correct submission for KIS tasks
submissions_per_team_task = combine(groupby(submissions, [:team, :group, :status, :task]), :status => length => :count)
duplicates = (.!contains.(submissions_per_team_task[:, :group], "AD")) .& (submissions_per_team_task[:, :status] .== "CORRECT") .& (submissions_per_team_task[:, :count] .> 1)
submissions_per_team_task[duplicates, :count] = repeat([1], sum(duplicates))

submissions_per_team = combine(groupby(submissions_per_team_task, [:team, :group, :status]), :count => sum => :count)
sort!(submissions_per_team, [:group, :status])
submissions_per_team = @rorderby submissions_per_team findfirst(==(:team), oder)

kis = submissions_per_team[.!contains.(submissions_per_team[:, :group], "AD"), :]
kis[!, :key] = map(x -> "$(x[:group]) - $(x[:status])", eachrow(kis))

#hack to populate missing combinations with 0
h = collect(Iterators.product(unique(kis[:, :team]), unique(kis[:, :key])))[:]
kis = vcat(kis, DataFrame(team = map(x -> x[1], h), group = "", status = "", count = 0, key = map(x -> x[2], h)))

kis = combine(groupby(kis, [:team, :key]), :count => sum => :count)
sort!(kis, :key)
kis = @rorderby kis findfirst(==(:team), oder)


pos = collect(Iterators.flatten(([[i, i, i, i, i, i, i, i] for i in 1:team_count])))
dodge = collect(Iterators.flatten(([[1, 1, 2, 2, 3, 3, 4, 4] for i in 1:team_count])))
stack = collect(Iterators.flatten(([[1, 1, 1, 1, 1, 1, 1, 1] for i in 1:team_count])))
col = collect(Iterators.flatten(([[1, 2, 3, 4, 5, 6, 7, 8] for i in 1:team_count])))
colors = palette("Paired", 10)
colors = colors[[2,1,4,3,10,9,8,7]]

fig = Figure()

ax = Axis(fig[1, 1],
xlabel = "Team",
ylabel = "Number of Submissions",
xticks = (1:team_count, team_names),
yticks = (0:2:14),
xticklabelrotation = pi/4,
title = "")

barplot!(ax,
    pos, kis[:, :count],
    dodge = dodge,
    stack = stack,
    color = colors[col]
)

labels = kis[1:8, :key]

Legend(fig[2,1], [PolyElement(polycolor = colors[i]) for i in 1:8], labels, "Task Type", orientation = :horizontal, framevisible = false, nbanks = 2)

save("plots/kis_status_count.pdf", fig)


avs = submissions_per_team[contains.(submissions_per_team[:, :group], "AD"), :]

#hack to populate missing combinations with 0
h = collect(Iterators.product(unique(avs[:, :team]), unique(avs[:, :status])))[:]
avs = vcat(avs, DataFrame(team = map(x -> x[1], h), group = "AD", status = map(x -> x[2], h), count = 0), DataFrame(team = map(x -> x[1], h), group = "AD-NOVICE", status = map(x -> x[2], h), count = 0))

avs = combine(groupby(avs, [:team, :group, :status]), :count => sum => :count)
avs[!, :combined] = avs[:, :group] .* " - " .* avs[:, :status]
sort!(avs, :combined)
avs = @rorderby avs findfirst(==(:team), oder)


pos = collect(Iterators.flatten(([[i, i, i, i, i, i] for i in 1:team_count])))
grp = collect(Iterators.flatten(([[1, 2, 3, 4, 5, 6] for i in 1:team_count])))
colors = palette("Set2", 6)

fig = Figure()

ax = Axis(fig[1, 1],
xlabel = "Team",
ylabel = "Number of Submissions",
xticks = (1:team_count, team_names),
yticks = (0:100:500),
xticklabelrotation = pi/4,
title = "")

barplot!(ax,
    pos, avs[:, :count],
    dodge = grp,
    color = colors[grp]
)

labels = avs[1:6, :combined]

Legend(fig[2,1], [PolyElement(polycolor = colors[i]) for i in 1:6], labels, "Status", orientation = :horizontal, framevisible = false, nbanks = 2)

save("plots/adhoc_status_count.pdf", fig)



## time until first (correct) submission per team and type

time_to_first_submission = combine(groupby(submissions, [:team, :group, :task]), :time => minimum => :first)

time_to_first_submission[!, :first] ./= 60_000

sort!(time_to_first_submission, :group)

time_to_first_submission = @rorderby time_to_first_submission findfirst(==(:team), oder)


colors = palette("Paired", 6)

team_to_id = Dict(zip(oder, collect(1:team_count)))
xs = map(x -> get(team_to_id, x, 0), time_to_first_submission[:, :team])

type_to_id = Dict(["AD" => 1, "AD-NOVICE" => 2, "KIS" => 3, "KIS-NOVICE" => 4, "QA" => 5, "QA-NOVICE" => 6])
dodge = map(x -> get(type_to_id, x, 0), time_to_first_submission[:, :group])

fig = Figure()

ax = Axis(fig[1, 1],
xlabel = "Team",
ylabel = "Minutes",
xticks = (1:team_count, team_names),
yticks = (0:1:8),
xticklabelrotation = pi/4,
title = "")

boxplot!(ax, xs, time_to_first_submission[:, :first],
dodge = dodge,
color = colors[dodge],
gap = 0.4
)

labels = ["AD", "AD-NOVICE", "KIS", "KIS-NOVICE", "QA", "QA-NOVICE"]

Legend(fig[2,1], [PolyElement(polycolor = colors[i]) for i in 1:6], labels, "Task Type", orientation = :horizontal, framevisible = false)

save("plots/time_to_first_submission.pdf", fig)



time_to_first_correct_submission = combine(groupby(submissions[submissions[:, :status] .== "CORRECT", :], [:team, :group, :task]), :time => minimum => :first)

time_to_first_correct_submission[!, :first] ./= 60_000

sort!(time_to_first_correct_submission, :group)

time_to_first_correct_submission = @rorderby time_to_first_correct_submission findfirst(==(:team), oder)

xs = map(x -> get(team_to_id, x, 0), time_to_first_correct_submission[:, :team])
dodge = map(x -> get(type_to_id, x, 0), time_to_first_correct_submission[:, :group])

fig = Figure()

ax = Axis(fig[1, 1],
xlabel = "Team",
ylabel = "Minutes",
xticks = (1:team_count, team_names),
yticks = (0:1:8),
xticklabelrotation = pi/4,
title = "")

boxplot!(ax, xs, time_to_first_correct_submission[:, :first],
dodge = dodge,
color = colors[dodge],
gap = 0.4
)


Legend(fig[2,1], [PolyElement(polycolor = colors[i]) for i in 1:6], labels, "Task Type", orientation = :horizontal, framevisible = false)

save("plots/time_to_first_correct_submission.pdf", fig)