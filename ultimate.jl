using ProgressMeter

println("Loading Images.")

using Images
println("Loaded Images.")

type Square
    rows::Array{Array{Int64, 1}, 1}
end

type Move
    previous::(Int64, Int64)
    move::(Int64, Int64)
end

#clear board rows after it has it's children generated. Save the last move of the board

type Board
    rows::Array{Array{Square, 1}, 1}
    owner_square::Square

    owner::Int64

    previous_move::Move

    function Board(rows::Array{Array{Square, 1}, 1}, previous_move::Move)
        osquare = owner_square(rows)

        return new(rows, osquare, owner(osquare, true), previous_move)
    end

    Board(rows::Array{Array{Square, 1}, 1}, owner_square::Square, owner::Int64, previous_move::Move) = new(rows, owner_square, owner, previous_move)
end

type Goal
    goal_type::ASCIIString
    marker::Int64

    goal

    truth_value::Bool

    tester

    function Goal(goal_type::ASCIIString, marker::Int64, goal, truth_value::Bool)
        tester = goal_own
        if goal_type == "own"
            tester = goal_own
        elseif goal_type == "move"
            tester = goal_move
        elseif goal_type == "own_count"
            tester = goal_own_count
        elseif goal_type == "win"
            tester = goal_win
        else
            throw("Invalid goal type: $goal_type")
        end

        return new(goal_type, marker, goal, truth_value, tester)
    end

    Goal(goal_type::ASCIIString, goal) = Goal(goal_type, "", goal, true)
    Goal(goal_type::ASCIIString, goal, truth_value::Bool) = Goal(goal_type, "", goal, true)
end

type Outcome
    board::Board
    move_sequence::Array{Move, 1}

    parent
    children::Array{Outcome, 1}
    siblings::Array{Outcome, 1}

    total_score::Int64 #The sum of all goal scores of all children
    total_outcomes::Int64 #The total number of children

    goal_score::Int64 #The number of goals that this Outcome meets

    is_finished::Bool

    function Outcome(board::Board, move_sequence::Array{Move, 1}, parent, children::Array{Outcome, 1},
                     siblings::Array{Outcome, 1}, total_score::Int64, total_outcomes::Int64, goal_score::Int64,
                     is_finished::Bool)
        return new(board, move_sequence, parent, children, siblings, total_score, total_outcomes, goal_score, is_finished)
    end

    function Outcome(board::Board, move_sequence::Array{Move, 1}, parent, total_score::Int64,
                     total_outcomes::Int64, goal_score::Int64, is_finished::Bool)
        return new(board, move_sequence, parent, Outcome[], Outcome[], total_score, total_outcomes, goal_score, is_finished)
    end

    function Outcome(board::Board, goals::Array{Goal, 1})
        parent = nothing
        move_sequence = Move[]
        goal_score = get_goal_score(board, goals)
        is_finished = has_owner(board)

        return new(board, move_sequence, parent, Outcome[], Outcome[], goal_score, 0, goal_score, is_finished)
    end
end

type UTTFile
    board::Board
    markers::Array{Int64, 1}

    goals::Array{Goal, 1}

    max_steps::Int64
    steps::Int64
    path_steps::Int64

    score_threshold::Float64
end

#Completely flattens an array
flatten{T}(a::Array{T,1}) = any(map(x -> isa(x, Array), a)) ? flatten(vcat(map(flatten, a)...)) : a
flatten{T}(a::Array{T}) = reshape(a, prod(size(a)))
flatten(a) =  a

function remove!(a, v)
    for (i, test_v) in enumerate(a)
        if test_v == v
            deleteat!(a, i)

            return a
        end
    end
end

function count_filled_cells(b::Board)
    count = 0

    for row in b.rows
        for square in row
            for srow in square.rows
                for cell in srow
                    if cell != 0
                        count += 1
                    end
                end
            end
        end
    end

    return count
end

function average_pairs(pairs)
    total = (0, 0)

    for (a, b) in pairs
        total = (total[1] + a, total[2] + b)
    end

    return (total[1] / length(pairs), total[2] / length(pairs))
end

average_points(points) = average_pairs(map(i -> (i.x, i.y), points))

function ==(a::Move, b::Move)
    (pxa, pya), (mxa, mya) = a.previous, a.move
    (pxb, pyb), (mxb, myb) = b.previous, b.move

    if pxa != pxb
        return false
    elseif pya != pyb
        return false
    elseif mxa != mxb
        return false
    elseif mya != myb
        return false
    else
        return true
    end
end

function construct_best_move_tree(os::Array{Outcome, 1}, key=outcome_score, moves=1)
    outcomes = filter(outcome -> length(outcome.move_sequence) == moves, os)

    sort!(outcomes, by=key)
    best_move = outcomes[end].move_sequence[end]

    candidates = (Move => Any)[]
    for outcome in os
        if length(outcome.move_sequence) == (moves + 1) && outcome.move_sequence[moves] == best_move
            next_outcomes = filter(o -> length(o.move_sequence) > (moves + 1) && o.move_sequence[moves + 1] == outcome.move_sequence[end], os)

            if length(next_outcomes) > 0
                candidates[outcome.move_sequence[end]] = construct_best_move_tree(next_outcomes, key, moves + 2)
            else
                candidates[outcome.move_sequence[end]] = true
            end
        end
    end

    return {best_move => candidates}
end

test_data() = {[1,2,3,5,4], [1,2,3,4,5], [1,2,4,5,3], [1,3,4,5,3], [1,3,3,5,3], [1,3,5,2,1], [1,4,6,1,1]}
function build_tree(a, i=1, verbose=0)
    result = (Any => Any)[]
    processed = (Int64 => Bool)[]

    for (data_i, data) in enumerate(a)
        if length(data) > i
            if haskey(processed, data_i)
                continue
            end
            matches = Any[data]

            for (check_i, check) in enumerate(a)
                if length(check) > i
                    if check_i > data_i && !haskey(processed, check_i)
                        if data[i] == check[i]
                            push!(matches, check)

                            processed[check_i] = true
                        end
                    end
                end
            end

            # if verbose > 1
            #     println("$(repeat("  ", i - 1))$i: $(data[i])")
            # end

            result[data[i]] = build_tree(matches, i + 1, verbose)
            # if verbose > 3
            #     println("$(repeat("  ", i - 1))$(length(processed)) processed so far, with $(length(matches)) matches for this element ($data_i).")
            # end
        else
            result[data[end]] = nothing
        end
    end

    return result
end

function outcome_score(o::Outcome)
    res, owner = outcome_is_finished(o)

    base_score = 0

    if res
        if owner == 1
            base_score = 100
        else
            base_score = -100
        end
    end

    if o.total_outcomes > 0
        return base_score + o.total_score / o.total_outcomes
    else
        return base_score + o.total_score
    end
end

function increment_outcome_score!(o::Outcome, amount::Int64, total_outcome_amount::Int64)
    o.total_score += amount
    o.total_outcomes += total_outcome_amount

    if o.parent != nothing
        increment_outcome_score!(o.parent, amount, total_outcome_amount)
    end
end

function visualize_tree(t, indent="")
    try
        for (i, rest) in t
            println("$indent- $i")
            visualize_tree(rest, indent * "|  ")
        end
    catch
    end
end

blank_square() = Square(Array{Int64, 1}[[0,0,0],[0,0,0],[0,0,0]])
blank_board() = Board(Array{Square, 1}[
        [blank_square(), blank_square(), blank_square()],
        [blank_square(), blank_square(), blank_square()],
        [blank_square(), blank_square(), blank_square()]], Move((0, 0), (0, 0)))

function row_owner(r)
    first = r[1]

    for t in r
        if t != first
            return 0
        end
    end

    return first
end

#Returns the diagonals of a square jagged array.
function diagonals(ss)
    first_diag = [ss[i][i] for i=1:length(ss)]
    second_diag = [ss[i + 1][length(ss) - i] for i=0:(length(ss) - 1)]

    return {first_diag, second_diag}
end

columns(a) = [[a[y][x] for y = 1:length(a)] for x=1:length(a)]

#Returns the owning marker in a square if there is one, or ' ' if there isn't.
function owner(s::Square, check_has_more=false)
    for row in s.rows
        res = row_owner(row)
        if res > 0
            return res
        end
    end

    for row in columns(s.rows)
        res = row_owner(row)
        if res > 0
            return res
        end
    end

    for row in diagonals(s.rows)
        res = row_owner(row)
        if res > 0
            return res
        end
    end

    # if check_has_more
    #     xs = 0
    #     os = 0
    #
    #     for x in 1:3
    #         for y in 1:3
    #             if s.rows[x][y] == 0
    #                 return 0
    #             elseif s.rows[x][y] == 1
    #                 xs += 1
    #             else
    #                 os += 1
    #             end
    #         end
    #     end
    #
    #     if xs > os
    #         return 1
    #     else
    #         return 2
    #     end
    # else
        return 0
    # end
end

owner_square(rows::Array{Array{Square, 1}, 1}) = Square(map(row -> map(owner, row), rows))
owner_square(b::Board) = Square(map(row -> map(owner, row), b.rows))

owner(b::Board) = b.owner

has_owner(s) = owner(s, false) > 0
has_owner(b::Board) = b.owner > 0
no_owner(s) = owner(s, false) == 0
no_owner(b::Board) = b.owner == 0

#Returns a list of all tuples that contain squares without a marker.
function all_moves(s::Square)
    result = (Int64, Int64)[]

    for (ix, x) in enumerate(s.rows)
        for (iy, y) in enumerate(x)
            if y == 0
                push!(result, (ix, iy))
            end
        end
    end

    return result
end

function all_open_moves(b::Board)
    result = Move[]

    for x in 1:3
        for y in 1:3
            if no_owner(b.rows[x][y])
                open_moves = all_moves(b.rows[x][y])
                append!(result, map(move -> Move((x, y), move), open_moves))
            end
        end
    end

    return result
end

function all_moves(b::Board)
    x, y = b.previous_move.move

    if x == 0 && y == 0 #If they're 0s, then its the first move, so we can go anywhere
        return all_open_moves(b)
    end

    if no_owner(b.rows[x][y]) #If the square hasn't already been taken, then we can only go in this square
        open_moves = all_moves(b.rows[x][y])

        #If the square is completey filled, then we can also go anywhere
        if length(open_moves) == 0
            return all_open_moves(b)
        else
            return map(i -> Move(i[1], i[2]), collect(zip(fill((x, y), length(open_moves)), open_moves)))
        end
    else #If it has been taken, we can now go in any square
        return all_open_moves(b)
    end
end

all_moves(outcome::Outcome) = all_moves(outcome.board)

function do_move(s::Square, marker::Int64, move::(Int64, Int64))
    rows = deepcopy(s.rows)

    rows[move[1]][move[2]] = marker

    return Square(rows)
end

function do_move(b::Board, marker::Int64, move::Move, goals::Array{Goal, 1})
    rows = deepcopy(b.rows)

    prev_x, prev_y = move.previous

    rows[prev_x][prev_y] = do_move(rows[prev_x][prev_y], marker, move.move)

    board = Board(rows, move)
    parent = nothing
    move_sequence = [move]
    goal_score = get_goal_score(board, goals)
    is_finished = has_owner(board)

    return Outcome(board, move_sequence, parent, goal_score, 0, goal_score, is_finished)
end

function do_move(outcome::Outcome, marker::Int64, move::Move, goals::Array{Goal, 1})
    rows = deepcopy(outcome.board.rows)

    prev_x, prev_y = move.previous

    rows[prev_x][prev_y] = do_move(rows[prev_x][prev_y], marker, move.move)

    board = Board(rows, move)
    parent = outcome
    move_sequence = vcat(outcome.move_sequence, move)
    goal_score = get_goal_score(board, goals)# + div(length(outcome.move_sequence) + 1, 2)
    is_finished = has_owner(board)

    return Outcome(board, move_sequence, parent, goal_score, 0, goal_score, is_finished)
end

do_all_moves(s::Square, marker::Int64) = map(move -> do_move(a, marker, move), all_moves(a))

function do_all_moves(b::Board, goals::Array{Goal, 1}, marker)
    o = Outcome(b, goals)

    return do_all_moves(o, goals, marker)
end

function do_all_moves(o::Outcome, goals::Array{Goal, 1}, marker=-1)
    if length(o.children) > 0 #If we've already generated the children, we don't need to do it again.
        return o.children
    else
        if marker == -1
            marker = current_move(o)
        end

        res, owner = outcome_is_finished(o)
        if !res
            for move in all_moves(o)
                outcome = do_move(o, marker, move, goals)
                push!(o.children, outcome)
            end

            for child in o.children
                child.siblings = o.children
            end

            # resize!(o.board.rows, 0)

            return o.children
        else
            return Outcome[]
        end
    end
end

get_solved(a) = filter(has_owner, a)

function goal_own(b::Board, marker::Int64, goal::(Int64, Int64), truth_value::Bool)
    if (b.owner_square.rows[goal[1]][goal[2]] == marker) == truth_value
        return 1
    else
        return 0
    end
end

function goal_move(b::Board, marker::Int64, goal::(Int64, Int64), truth_value::Bool)
    if (b.previous_move == goal) == truth_value
        return 1
    else
        return 0
    end
end

goal_own_count(b::Board, marker::Int64, goal, truth_value::Bool) = owned_squares(b, marker)

function goal_win(b::Board, marker::Int64, goal, truth_value::Bool)
    if b.owner == marker
        return 100
    else
        if b.owner != 0
            return -100
        else
            return 0
        end
    end
end

meets_goal(b::Board, goal::Goal) = goal.tester(b, goal.marker, goal.goal, goal.truth_value) > 0

function meets_goals(b::Board, goals::Array{Goal, 1})
    for goal in goals
        if !meets_goal(b, goal)
            return false
        end
    end

    return true
end

function get_goal_score(b::Board, goals::Array{Goal, 1})
    score = 0

    for goal in goals
        score += goal.tester(b, goal.marker, goal.goal, goal.truth_value)
        if meets_goal(b, goal)
            score += 1
        end
    end

    return score
end

function owned_squares(b::Board, marker::Int64)
    count = 0

    for x in 1:3
        for y in 1:3
            s_owner = b.owner_square.rows[x][y]
            if s_owner == marker
                count += 1
            elseif s_owner > 0
                count -= 1
            end
        end
    end

    return count
end

function get_outcomes(b_list::Array{Outcome, 1}, self, markers,
                      goals::Array{Goal, 1}, max_steps=-1, verbose=0, progress_bar=nothing)
    if progress_bar != nothing
        if progress_bar.n - progress_bar.counter == max_steps
            next!(progress_bar)
        end
    end

    result = Array{Outcome, 1}[]

    for b in b_list
        if !b.is_finished
            b_res = do_all_moves(b, goals)

            valid = b_res
        else
            valid = [b]
        end

        #We add to this anyway, even if length(not_success) is 0, because we use it later for comparison.
        push!(result, valid)
    end

    if max_steps == 1
        return flatten(result)
    else
        final_result = Outcome[]

        for next_outcome_list in result
            next_b_list = Outcome[]
            finished_b_list = Outcome[]
            for next_outcome in next_outcome_list
                if next_outcome.is_finished
                    push!(finished_b_list, next_outcome)
                else
                    push!(next_b_list, next_outcome)
                end
            end

            if length(next_b_list) > 0
                next_res = get_outcomes(next_b_list, self, reverse(markers), goals, max_steps - 1, verbose, progress_bar)

                if length(next_res) > 0
                    append!(final_result, next_res)
                end
            end

            if length(finished_b_list) > 0
                append!(final_result, finished_b_list)
            end
        end

        return final_result
    end
end

function outcome_is_finished(o::Outcome)
    if o.is_finished
        return (o.is_finished, o.board.owner)
    else
        current_mover = current_move(o)

        all_finished = length(o.children) > 0

        for child in o.children
            child_is_finished, child_owner = outcome_is_finished(child)

            #if any children finished, and we won, that means that the outcome is finished
            #because, naturally, we'd choose the winning move if there is one.
            if child_is_finished
                if child_owner == current_mover
                    o.is_finished = true
                    o.board.owner = child_owner

                    return (o.is_finished, o.board.owner)
                end
            else
                all_finished = false
            end
        end

        if all_finished
            o.is_finished = true
            o.board.owner = last_move(o) #None of the owners were us, so it's them.
        end

        return (o.is_finished, o.board.owner)
    end
end

function lookahead_outcomes(base::Outcome, self, markers, goals::Array{Goal, 1}, max_steps, verbose)
    result = Outcome[]

    # println("$(base.move_sequence): $(length(all_moves(base))) moves.")
    for outcome in do_all_moves(base, goals)
        res = get_outcomes([outcome], self, reverse(markers), goals, max_steps, verbose)

        first_calc = outcome.total_outcomes == 0

        if length(res) > 0
            #If we haven't already calculated this before
            if first_calc
                outcome.total_score = sum(map(r -> r.goal_score, res)) + outcome.goal_score

                outcome.total_outcomes = length(res) + 1
            end

            push!(result, outcome)
        else
            outcome.total_score = 0

            outcome.total_outcomes = 1
        end

        if first_calc
            increment_outcome_score!(outcome.parent, outcome.total_score + outcome.goal_score, outcome.total_outcomes)
        end
    end

    return result
end

function get_highest_parent(o::Outcome, self, markers)
    #If it's our turn, then we can go all the way back up to the top.
    if self == markers[1]
        end_point = 0
    else
        end_point = 1
    end

    while length(o.move_sequence) > end_point
        o = o.parent #Go up one level.
    end

    return o
end

function last_move(o::Outcome)
    if length(o.move_sequence) % 2 == 0
        return 2
    else
        return 1
    end
end

function current_move(o::Outcome)
    if last_move(o) == 1
        return 2
    else
        return 1
    end
end

function current_markers(o::Outcome)
    if last_move(o) == 1
        return [2,1]
    else
        return [1,2]
    end
end

function get_available_outcomes(o::Outcome, closed::Set{Outcome}, self, markers,
                                goals::Array{Goal, 1}, max_steps, verbose)
    highest_parent = get_highest_parent(o, self, markers) #Get the top level node

    #The initial candidates are the highest_parent's children.
    candidates = lookahead_outcomes(highest_parent, self, markers, goals, max_steps, verbose)

    results = Outcome[]

    while length(candidates) > 0
        next_candidate = pop!(candidates)

        # print("\r$(length(candidates)) candidates left to process.")

        #If we've already processed this one, try its children
        if next_candidate in closed
            append!(candidates, lookahead_outcomes(next_candidate, self, current_markers(next_candidate), goals, max_steps, verbose))
        else #If we haven't, check if it's was just our move in this game. If it was, then it's a candidate.
            if last_move(next_candidate) == markers[1]
                push!(results, next_candidate)
            end
        end
    end

    #We want the best ones to come last
    #If it's our (self) turn, that means highest score
    #if it's not our turn, that means lowest score.
    sort!(results, by=outcome_score, rev=self != markers[1])

    return results
end

function display_move_sequence(moves::Array{Move, 1})
    if length(moves) >= 2
        return "$(moves[1])...$(moves[end])"
    else
        return "$moves"
    end
end

function get_outcome_sequence(o::Outcome)
    outcome_sequence = Outcome[]
    while length(o.move_sequence) > 0
        push!(outcome_sequence, o)

        o = o.parent
    end

    return reverse(outcome_sequence)
end

function visualize_outcome_sequence(outcomes::Array{Outcome, 1})
    for outcome in outcomes
        if length(outcome.move_sequence) > 0
            println(outcome.move_sequence[end])
        end

        visualize_board(outcome.board)
    end

    return true
end

function remove_outcomes!(list::Array{Outcome, 1}, o::Outcome, remove_siblings)
    remove!(list, o)

    for child in o.children
        remove_outcomes!(list, child, false)
    end

    if remove_siblings
        for sibling in o.siblings
            remove_outcomes!(list, sibling, false)
        end
    end
end

function show_all_children(o::Outcome, indent=0)
    println("$(repeat("    ", indent))$(o.move_sequence): ($(last_move(o)), $(outcome_score(o))); Owner: $(outcome_is_finished(o))")

    for child in o.children
        show_all_children(child, indent + 1)
    end
end

function path_outcomes(o::Outcome, self, markers, goals::Array{Goal, 1}, score_threshold, max_steps=4, path_steps=2, verbose=0)
    current = o

    closed = Set{Outcome}()
    self_wins = Set{Outcome}()
    opponent_wins = Set{Outcome}()

    self_open = get_available_outcomes(current, closed, self, markers, goals, path_steps, verbose)
    opponent_open = Outcome[]

    first_move = nothing

    previous_available = Outcome[]

    while true
        if verbose > 0
            println("")
        end

        done = false
        for (i, move) in enumerate(o.children)
            oscore = outcome_score(move)
            if oscore > score_threshold
                push!(closed, move)
                done = true
                break
            end

            if verbose > 0
                println("$(move.move_sequence): $(move.total_outcomes): $oscore < $score_threshold")
            end
        end

        if done
            break
        end

        if verbose > 2
            write_outcome("current_run.txt", current)
        end

        if verbose > 0
            if self == markers[1]
                print("\rOur turn.")
            else
                print("\rTheir turn.")
            end
        end

        if self == markers[1]
            sort!(self_open, by=outcome_score)
        else
            sort!(opponent_open, by=outcome_score, rev=true)
        end

        #Get all the available options
        # available = get_available_outcomes(current, closed, self, markers, goals, path_steps, verbose)
        if self == markers[1]
            available = self_open
        else
            available = opponent_open
        end

        # println("$(length(available)) == $(length(get_available_outcomes(current, closed, self, markers, goals, path_steps, verbose)))")
        #
        # println("")
        # for i in available
        #     println("$(i.move_sequence): $(outcome_score(i))")
        #     # show_all_children(i)
        # end
        #
        # println("-------------------------")
        #
        # for i in get_available_outcomes(current, closed, self, markers, goals, path_steps, verbose)
        #     println(i.move_sequence)
        # end
        #
        # @assert length(available) == length(get_available_outcomes(current, closed, self, markers, goals, path_steps, verbose))

        if length(available) == 0
            if length(previous_available) > 0
                if verbose > 0
                    print(" No options for $(markers[1]), switching back to $(markers[2]).")
                end

                markers = reverse(markers)

                continue
            end

            if length(all_open_moves(current.board)) == 0 #if there aren't any moves left, then we've tied.
                break
            end

            if verbose > 0
                println("")
            end

            if self == markers[1] && length(opponent_wins) > 0
                # if verbose > 0
                    println("They won the game.")
                # end

                closed = sort(collect(closed), by=outcome_score)

                # move_sequences = map(outcome -> outcome.move_sequence, opponent_wins)

                return (true, construct_best_move_tree(closed, outcome -> outcome_score(outcome)))
            elseif length(self_wins) > 0
                # if verbose > 0
                    println("We won the game!")
                # end

                closed = sort(collect(closed), by=outcome_score)

                # move_sequences = map(outcome -> outcome.move_sequence, self_wins)

                return (true, construct_best_move_tree(closed, outcome -> outcome_score(outcome)))
            else
                # if verbose > 0
                    println("No possible options.")
                # end

                break
            end
        end

        # for outcome in available
        #     println("Outcome ($(length(outcome.move_sequence))): $(outcome.move_sequence) ($(outcome_score(outcome)))")
        # end

        if verbose > 0
            print(" $(length(available)) options. ($(length(self_wins)), $(length(opponent_wins))).")
        end

        best = nothing

        #Avoid making a losing move at all costs.
        while length(available) > 0
            if best == nothing
                best = pop!(available)
            end

            if length(available) == 0
                break
            end

            if best in opponent_wins && self == markers[1]
                best = pop!(available)
                remove_outcomes!(available, best, true)
            elseif best in self_wins && self != markers[1]
                best = pop!(available)
                remove_outcomes!(available, best, true)
            else
                # println("")
                res, owner = outcome_is_finished(best)

                if res
                    if owner == self
                        push!(self_wins, best)
                    else
                        push!(opponent_wins, best)
                    end

                    push!(closed, best)

                    #If this move ends in a loss for the current mover (markers[1]), then we obviously don't want to make it
                    if owner == markers[1]
                        break
                    else
                        best = pop!(available)
                        remove_outcomes!(available, best, true)
                    end
                else
                    break
                end
            end
        end

        # print(" $(length(available)) options left.")

        if verbose > 0
            if self == markers[1]
                print(" We chose ($(length(best.move_sequence))): $(display_move_sequence(best.move_sequence)) ($(outcome_score(best)))")
            else
                print(" They chose ($(length(best.move_sequence))): $(display_move_sequence(best.move_sequence)) ($(outcome_score(best)))")
            end
        end

        if !(current in closed)
            push!(closed, current)
        end

        #This means that there was no way to avoid a finished outcome
        res, res_owner = outcome_is_finished(o)
        if res
            if verbose > 0
                println("")
            end

            if res_owner == self
                # if verbose > 0
                    println("Outcomes finished, we won the game!")
                # end

                move_sequences = map(outcome -> outcome.move_sequence, self_wins)
            else
                # if verbose > 0
                    println("Outcomes finished, they won the game.")
                # end

                move_sequences = map(outcome -> outcome.move_sequence, opponent_wins)
            end

            return (true, build_tree(move_sequences, 1, verbose))
        end

        children = lookahead_outcomes(best, self, markers, goals, path_steps, verbose)

        if self == markers[1]
            for child in children
                if !(child in closed)
                    push!(opponent_open, child)
                end
            end
        else
            for child in children
                if !(child in closed)
                    push!(self_open, child)
                end
            end
        end

        current = best

        #It can only end on our turn
        if self == markers[1]
            if length(current.move_sequence) >= max_steps
                # if verbose > 0
                    println("Hit max steps.")
                # end

                break
            end
        end

        markers = reverse(markers)

        previous_available = available

        if first_move == nothing
            first_move = current.move_sequence[1]
        elseif first_move != current.move_sequence[1]
            opponent_open = get_available_outcomes(current, closed, self, markers, goals, path_steps, verbose)
            first_move = current.move_sequence[1]
        end
    end

    closed = sort(collect(closed), by=outcome -> outcome_score(outcome))

    return (false, construct_best_move_tree(closed, outcome -> outcome_score(outcome)))
end

function input_board(previous_move)
    rows = map(i -> convert(ASCIIString, i), [replace(readline(), "\n", "") for i in 1:11])

    return parse_board(rows, previous_move)
end

function parse_board(lines::Array{ASCIIString, 1}, previous_move::(Int64, Int64))
    b = blank_board()

    lines = filter(line -> !contains(line, "-"), lines) #Remove the blank vertical separator lines.
    for (i, line) in enumerate(lines)
        lines[i] = replace(line, "|", "")
    end

    for x in 1:3
        for y in 1:3
            for sx in 1:3
                for sy in 1:3
                    b = do_move(b, int(string(lines[(x - 1) * 3 + sx][(y - 1) * 3 + sy])), Move((x, y), (sx, sy)), Goal[])
                end
            end
        end
    end

    return Board(b.board.rows, Move((0, 0), previous_move))
end

remove_newlines(s::ASCIIString) = replace(replace(s, "\r", ""), "\n", "")

function read_file_lines(fname::ASCIIString)
    f = open(fname)
    lines = map(remove_newlines, readlines(f))
    close(f)

    return lines
end

function parse_pair(pair_str, pair_type)
    vals = map(pair_type, split(pair_str, ","))

    return (vals[1], vals[2])
end

#["own", "move", "own_count", "win"]
function parse_goal(params)
    params = split(params)

    goal_type, marker, goal, truth_value = "", 0, 0, true

    if length(params) < 2
        throw("Incorrect number of arguments for goal: $(length(params))")
    else
        goal_type = params[1]

        if length(params) == 2
            #There are only two types of goals that can be specified using only two parameters
            if !(goal_type in ["win", "own_count"])
                throw("Invalid number of arguments for goal: $goal_type")
            end

            if goal_type == "win"
                marker = int(params[2])
            elseif goal_type == "own_count"
                marker = int(params[2])
            end
        elseif length(params) < 5
            if params[end] == "true"
                truth_value = true
            elseif params[end] == "false"
                truth_value = false
            end

            if goal_type == "own"
                marker = int(params[2])
                goal = parse_pair(params[3], int)
            elseif goal_type == "move"
                marker = int(params[2])
                goal = parse_pair(params[3], int)
            elseif goal_type == "own_count"
                marker = int(params[2])
            elseif goal_type == "win"
                marker = int(params[2])
            end
        else
            throw("Too many argument for goal: $(length(params))")
        end
    end

    return Goal(convert(ASCIIString, goal_type), marker, goal, truth_value)
end

function read_utt_file(fname::ASCIIString)
    lines = read_file_lines(fname)

    board = blank_board()
    markers = [1, 2]
    goals = Goal[]
    path_steps = 2
    max_steps = 1

    score_threshold = 10.0

    ignore_lines = 0

    for (i, line) in enumerate(lines)
        if ignore_lines > 0
            ignore_lines -= 1
            continue
        end

        if length(line) > 0
            if line[1] == '#' #Comment line
                continue
            end
        else
            continue
        end

        params = map(strip, split(line, ":"))

        if length(params) == 0 #Ignore blank links
            continue
        elseif params[1] == "markers"
            markers = map(i -> int(i), split(params[2], ","))
        elseif params[1] == "max_steps"
            max_steps = int(params[2])
        elseif params[1] == "path_steps"
            path_steps = int(params[2])
        elseif params[1] == "score_threshold"
            score_threshold = float(params[2])
        elseif params[1] == "board"
            previous_move = parse_pair(params[2], int)
            board = parse_board(lines[i + 1:i + 12], previous_move) #9 lines for the actual board, 2 for the separators.
            ignore_lines = 9
        elseif params[1] == "goal"
            push!(goals, parse_goal(params[2]))
        end
    end

    steps = max_steps# - count_filled_cells(board)

    println("Settings for $fname")
    println("markers: $markers")
    println("max_steps: $max_steps")
    println("path_steps: $path_steps")
    println("score_threshold: $score_threshold")
    println("steps: $steps")
    println("$(count_filled_cells(board)) filled cells.")

    return UTTFile(board, markers, goals, max_steps, steps, path_steps, score_threshold)
end

rand_choice(l) = l[rand(1:length(l))]

function run_utt_file(f::UTTFile, verbose=1)
    is_finished, move_tree = path_outcomes(Outcome(f.board, f.goals), f.markers[1], f.markers, f.goals, f.score_threshold, f.steps, f.path_steps, verbose)

    if verbose > 0
        if verbose > 1
            println("")
            if is_finished
                println("Calculated game winning tree:")
            end

            # visualize_tree(move_tree)
        end

        # println(move_tree)

        println("Suggested move: $(collect(keys(move_tree))[1])")
    end

    return move_tree
end

function visualize_square(s::Square)
    result = ""

    for (i, row) in enumerate(s.rows)
        result *= join(row, "|") * "\n"

        if i < 3
            result *= "-----\n"
        end
    end

    println(result)
end

function visualize_board(b::Board)
    result = ""

    for (isr, srow) in enumerate(b.rows)
        for i = 1:3
            result *= join([join(map(string, s.rows[i]), "|") for s in srow] , "||") * "\n"
        end

        if isr < 3
            result *= "-------------------\n"
        end
    end

    result = replace(result, "0", " ")
    result = replace(result, "1", "x")
    result = replace(result, "2", "o")

    println(result)
end

function output_board(b::Board)
    result = ""

    for (isr, srow) in enumerate(b.rows)
        for i = 1:3
            result *= join([join(map(string, s.rows[i])) for s in srow] , "|") * "|\n"
        end

        if isr < 3
            result *= "------------\n"
        end
    end

    return result
end

function play_self(template::ASCIIString)
    utt_file = read_utt_file(template)

    markers = [1,2]

    moves = 0

    while no_owner(utt_file.board)
        move_tree = run_utt_file(utt_file, 0)

        move = collect(keys(move_tree))[1]

        println("Move ($moves): $move")

        utt_file.board = do_move(utt_file.board, 1, move, utt_file.goals).board

        if markers[1] == 1
            visualize_board(utt_file.board)
        end

        utt_file.board = reverse_board(utt_file.board)

        if markers[1] == 2
            visualize_board(utt_file.board)
        end

        markers = reverse(markers)

        moves += 1
    end
end

function reverse_board(b::Board)
    board_output = output_board(b)

    board_output = replace(board_output, "1", "t")
    board_output = replace(board_output, "2", "1")
    board_output = replace(board_output, "t", "2")
    lines = split(board_output, "\n")
    lines = map(i -> convert(ASCIIString, i), lines)

    new_board = parse_board(lines, b.previous_move.move)

    return new_board
end

function read_utt_file_from_screen(filename::ASCIIString, template::ASCIIString, verbose)
    return read_utt_file_from_image(take_screenshot_mac(filename), template, verbose)
end

function read_utt_file_from_image(filename::ASCIIString, template::ASCIIString, verbose)
    base_utt_file = read_utt_file(template)

    groups = group_regions_by_colors(get_regions(filename, (450, 907, 203, 662), TestRange(500, 1500), verbose), 0.4)
    w = 907 - 450 + 1
    h = 662 - 203 + 1

    for (i, group) in enumerate(groups)
        if verbose > 0
            copy_img = show_on_img((w, h), group, SimpleColor(rand(1)[1], rand(1)[1], rand(1)[1]))
            imwrite(copy_img, "$filename-group-$i.png")
        end
    end

    if length(groups) > 3
        throw("More than three groups of regions ($(length(groups))) found in this image!")
    end

    square_start, square_spacing = 26, 40
    square_size = div(w - square_spacing * 2 - square_start * 2, 3)
    marker_size = div(square_size, 3) + 5

    previous_move = base_utt_file.board.previous_move

    found_previous_move = 0

    new_board = blank_board()

    for (i, group) in enumerate(groups)
        if verbose > 0
            println("Group $i:")
        end

        #This means its larger than the average square, so its the previous move indicators
        if average_width(group) > 31
            current_board_x = -1
            current_board_y = -1

            for i in group
                position = average_location(i.data)
                board_x = div(position.y - square_start, square_size + square_spacing) + 1
                board_y = div(position.x - square_start, square_size + square_spacing) + 1

                if current_board_x == -1
                    current_board_x = board_x
                elseif current_board_x != board_x
                    current_board_x = 0
                    current_board_y = 0

                    break
                end

                if current_board_y == -1
                    current_board_y = board_y
                elseif current_board_y != board_y
                    current_board_x = 0
                    current_board_y = 0

                    break
                end
            end

            previous_move = (current_board_x, current_board_y)

            found_previous_move = 1 #An integer not a bool as noted below.

            continue
        end

        #If we found the previous move, then the previous group isn't one of the markers, so we need to shift it back.
        if (i - found_previous_move) == 1
            marker = 1
        else
            marker = 2
        end

        for e in group
            position = average_location(e.data)

            #These are intentionally flipped, because do_move works with the coordinates flipped.
            board_x = div(position.y - square_start, square_size + square_spacing) + 1
            board_y = div(position.x - square_start, square_size + square_spacing) + 1
            square_x = div(position.y - square_start - (board_x - 1) * (square_size + square_spacing), marker_size) + 1
            square_y = div(position.x - square_start - (board_y - 1) * (square_size + square_spacing), marker_size) + 1

            if verbose > 0
                println("\tPosition: $position; Area: $(length(e.data)); (($board_x, $board_y), ($square_x, $square_y))")
            end

            new_board = do_move(new_board, marker, Move((board_x, board_y), (square_x, square_y)), Goal[]).board
        end
    end

    should_reverse = false

    base_board_output = output_board(base_utt_file.board)
    board_output = output_board(new_board)

    for i in 1:length(base_board_output)
        base_row = base_board_output[i]
        new_row = board_output[i]

        for mi in 1:length(base_row)
            if new_row[mi] != base_row[mi] && base_row[mi] != '0'
                should_reverse = true

                println("Flipping the board beacuse ($i, $mi) is $(base_row[mi]) for the template but $(new_row[mi]) for the image.")

                break
            end
        end

        if should_reverse
            break
        end
    end

    if should_reverse
        new_board = reverse_board(new_board)
    end

    new_board.previous_move = Move((0, 0), previous_move)
    base_utt_file.board = new_board

    if verbose > 0
        println("Outputting.")
        output_utt_file(base_utt_file, template)
    end

    return base_utt_file
end

function output_goal(goal::Goal)
    goal_type = string(goal.goal_type)
    marker = string(goal.marker)
    truth_value = string(goal.truth_value)
    goal = string(goal.goal)

    if goal_type == "win"
        return "$goal_type $marker $truth_value\n"
    elseif goal_type == "own_count"
        return "$goal_type $marker\n"
    elseif goal_type == "move"
        return "$goal_type $marker $goal $truth_value\n"
    elseif goal_type == "own"
        return "$goal_type $marker $goal $truth_value\n"
    end
end

function write_outcome(filename::ASCIIString, o::Outcome)
    writer = open(filename, "w")

    write(writer, output_board(o.board))

    close(writer)
end

function output_utt_file(utt_file::UTTFile, filename::ASCIIString)
    writer = open(filename, "w")

    write(writer, "markers: $(utt_file.markers[1]),$(utt_file.markers[2])\n")
    write(writer, "max_steps: $(utt_file.max_steps)\n")
    write(writer, "path_steps: $(utt_file.path_steps)\n")
    write(writer, "score_threshold: $(utt_file.score_threshold)\n")
    write(writer, "board: $(utt_file.board.previous_move.move[1]),$(utt_file.board.previous_move.move[2])\n")
    write(writer, output_board(utt_file.board))
    write(writer, "\n")

    for goal in utt_file.goals
        write(writer, "goal: " * output_goal(goal))
    end

    close(writer)
end

function handle_params(params, is_running=false)
    if length(params) > 0
        verbose = 3

        if !is_running
            file_name = convert(ASCIIString, params[1])

            if '/' in file_name
                separator = '/'
            else
                separator = '\\'
            end

            path_params = split(file_name, separator)
            path = join(path_params[1:end - 1], separator) * string(separator)
            fname = convert(ASCIIString, path_params[end])
        else
            path = "./"
            fname = convert(ASCIIString, params[1])
        end

        try
            if length(path) > 1
                println("Switching path to $path.")
                cd(path)

                include("ImageRegion.jl")
            end
        catch
        end

        if fname == "run" #Continuously run
            println("Running interactively.")

            return true
        elseif fname == "screen"
            if length(params) < 2
                throw("Not enough arguments for reading screen. Need a template file.")
            end

            println("Reading screen into file and running file.")
            println("Switching path to $path.")

            template_file = path * convert(ASCIIString, params[2])

            println("Running the current game on screen with the template file $template_file")

            @time best = run_utt_file(read_utt_file_from_screen("utt_file.png", template_file, 1), verbose);

            return best
        elseif fname == "read_screen"
            if length(params) < 2
                throw("Not enough arguments for reading screen. Need a template file.")
            end

            println("Reading the screen into a file.")

            template_file = path * convert(ASCIIString, params[2])

            println("Reading the screen into file: $template_file")

            @time best = read_utt_file_from_screen("utt_file.png", template_file, verbose);

            return best
        elseif fname == "process_image"
            if length(params) < 3
                throw("Not enough arguments for processing image. Should be: utt_run process_image image template")
            end

            println("Processing image.")

            image_file = path * convert(ASCIIString, params[2])
            template_file = path * convert(ASCIIString, params[3])

            println("Processing the image file $image_file with the template $template_file.")

            @time best = read_utt_file_from_image(image_file, template_file, verbose);

            return best
        elseif fname == "run_image"
            if length(params) < 3
                throw("Not enough arguments for running image. Should be: utt_run run_image image template")
            end

            println("Running image.")

            image_file = path * convert(ASCIIString, params[2])
            template_file = path * convert(ASCIIString, params[3])

            println("Processing the image file $image_file with the template $template_file.")

            @time best = run_utt_file(read_utt_file_from_image(image_file, template_file, 1), verbose);

            return best
        elseif fname == "help"
            println("Solves the game of Ultimate Tic Tac Toe.")

            println("Options:")
            println("\tutt_run filename - The default option. Runs the ultimate tic tac toe file specified.")
            println("\tutt_run screen template - Takes a screenshot, processes the image, outputs the new file data, then runs the template file.")
            println("\tutt_run read_screen template - Reads the screen with the template file and outputs the new file data.")
            println("\tutt_run process_image image template - Processes the image with the template file and outputs the new file data.")
            println("\tutt_run run_image image template - Processes the image with the template file, outputs the new file data, and then runs the template file.")
            println("\tutt_run help - Shows this screen.")
            println("\tutt_run run - Starts the interactive prompt, which runs commands continuously.")
            println("\tquit - Quits the interactive prompt.")

            return true
        elseif fname == "quit"
            println("Quitting.")
            return false
        else
            println("Running file $(path * fname)")

            try
                @time best = run_utt_file(read_utt_file(path * fname), verbose);

                return best
            catch e
                println(e)
                println("Could not find file $(path * fname)")
            end
        end
    end
end

res = handle_params(ARGS, false)

if res == true
    while true
        print(":> ") #Show prompt
        params = split(readline()[1:end - 1])

        res = handle_params(params, true)

        if res == false
            break
        end
    end
end
