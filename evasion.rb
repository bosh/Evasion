require 'socket'
Infinity = 1.0/0	#Only used to initialize distance values in the (currently broken Dec'10) A* implementation

#	The game server. Accepts inbound connections and reads messages in two different threads
#	and spawns games once there are enough ready players
class EvasionServer
	attr_accessor :server, :acceptor, :creator, :games, :connections, :results
	def initialize
		@games = []			#	No games to start
		@connections = []	#	No clients connected to start
		@results = []		#	No completed games to start
		start_server!
		start_acceptor!
		start_game_creator!
	end

	#	Start the server on the global port value and save it in a local variable
	def start_server!; @server = TCPServer.open($port) end

	#	Start the inbound connection acceptor
	def start_acceptor!
		$threads << @acceptor = Thread.new() do
			while true
				if new_connection = @server.accept
					puts "New connection accepted: #{new_connection}"
					@connections << new_connection #Save any inbound
				end
			end
		end
	end

	#	Start the connection reader to look for players sending JOIN and SPECTATE
	def start_game_creator!
		$threads << @creator = Thread.new() do
			ready_players = []
			spectators = []
			while true
				# Check every connection in the waiting queue for a JOIN or SPECTATE
				@connections.each do |c|
					line = c.readline
					if line =~ /JOIN\W+(\w+)/i	# A player is attempting to join the game, move them from waiting to READY
						puts "JOIN: #{$1} joined a game"
						ready_players << {:connection => c, :user => $1.strip}
						@connections.delete c
					elsif line =~ /SPECTATE/i
						puts "Spectator joined"
						spectators << c			# A spectator is ready to watch the next game, move the, to SPECTATORS
						@connections.delete c
					end
					if ready_players.size > 1	# If you have enough players to play
						puts "Two players have requested a game, spawning new game for:"
						p1 = ready_players.pop	# Get the first two ready players
						p2 = ready_players.pop
						specs = spectators.clone
						spectators = []			# Assign all specs to the new game and clear the spec list out
						puts "\tHunter: #{p1[:user]}\n\tPrey: #{p2[:user]}"
						new_game = Evasion.new(p1[:connection], p1[:user], p2[:connection], p2[:user], specs)
						# @games << new_game	# Leftover comments from multithreading with simultaneous games approach. Does not work well on energon.
						# $threads << Thread.new(new_game) do |game|
						# 	Thread.current.priority = 10	# Escalate the game's thread to always beat ACCEPTOR and CREATOR threads
							@results << new_game.play # @results << game.play
						# end
					end
				end
			end
		end
	end
end

#	An instance of the evasion game
class Evasion
	@@game_count = 1	# Incremented every time a game is spawned, used to assign unique ids
	attr_accessor :hunter, :prey, :board, :board_history, :walls, :current_player, :current_turn, :id, :spectators

	def initialize(connection_one, user_one, connection_two, user_two, spectators)
		@spectators = spectators
		setup_board!
		setup_players!(connection_one, user_one, connection_two, user_two)
		@board_history = []	# No history to start. Not currently used, but could be used to generate a replay (imagemagick => gif output)
		@walls = []			# No walls to start
		@id = @@game_count	# Assign a unique ID
		@@game_count += 1
	end

	#	Read the game parameters global hash and create the board with the correct dimensions
	#	Note that a dimension "500" means the board ranges from 0 to 499 inclusive
	#	The board is a 2d array, where board[y][x] is the value at (x,y)
	#	Note that for the visual display, the coordinate (0,0) is the upper left most point
	def setup_board!
		@board = Array.new($dimensions[:y]){ Array.new($dimensions[:x]) {:empty} }
	end

	#	Get the names and connections associated with each player and create new objects for them
	def setup_players!(hunter_connection, hunter_name, prey_connection, prey_name)
		@hunter = Hunter.new(self, hunter_connection, hunter_name)
		@prey = Prey.new(self, prey_connection, prey_name)
	end

	#	The gameplay loop. Starts at turn 0, increments turn counter every time through the loop
	#	Note that the number reported to a player is actually the ROUND number, which is turn/2
	#		i.e. both players may act in a single round, and a round has turns number round*2 and round*2 + 1
	def play
		@current_turn = 0
		@current_player = @hunter
		players.each{|p| p.write(game_parameters)}
		until is_game_over?
			pre_turn_wall_count = @walls.size
			report_state_to_spectators
			@current_player.take_turn
			# Only print the board every 10 turns or if a wall was added or removed
			print_minified_board() if @current_turn%10 == 0 || @walls.size != pre_turn_wall_count
			advance_turn!
			print "#{@current_turn}  "
		end
		result = report_winner
		cleanup_players!
		cleanup_spectators!
		result	# Returns this so the EvasionServer can save results
	end

	#	X, Y, Wall_Max, Hunter_Cooldown, Prey_Cooldown :: in string form, all taken from global values
	def game_parameters
		"(#{$dimensions[:x]}, #{$dimensions[:y]}) #{$wall_max}, #{$cooldown[:hunter]}, #{$cooldown[:prey]}"
	end

	#	The game serialized into the round, hunter state, prey state, and the walls
	#	Note, the presence of "YOURTURN" at the start implies that the server only sends state when it is a player's turn to act
	def game_state
		"YOURTURN #{self.current_round} #{@hunter.to_state}, #{@prey.to_state}, W[#{@walls.map{|w| w.to_state}.join(", ")}]"
	end

	#	Send the game state to all specs. Note that it includes "YOURTURN", but specs are write-only connections for the server, so they cannot take turns
	def report_state_to_spectators
		gs = game_state
		@spectators.each{|s| s.puts(gs)}
	end

	#	Turn number reported to players is actually 1/2 the turns played
	def current_round; (@current_turn / 2).floor end

	#	Game is over if either player has won
	def is_game_over?; won_by?(:hunter) || won_by?(:prey) end

	#	Hunter wins if either within distance or if the prey goes over time
	#	Prey wins if either it gets separated from the hunter or the hunter gets stuck or the hunter goes over time
	#	Return value is either FALSE or a string (thus truthy) containing the reason
	def won_by?(player)
		case player
		when :hunter
			if players_within_distance?
				"CAPTURE"
			elsif @prey.time_taken > $time_limit
				"TIMEOUT"
			else
				false
			end
		when :prey
			if players_surrounded?
				"ESCAPE"
			elsif hunter_trapped?
				"ESCAPE"
			elsif @hunter.time_taken > $time_limit
				"TIMEOUT"
			else
				false
			end
		end
	end

	#	If the hunter manages to make it such that every possible diagonal move is invalid for them, they are trapped
	def hunter_trapped?
		corners = []
		[-1, +1].each{|dx| [-1, +1].each{|dy| corners << {:x => @hunter.x + dx, :y => @hunter.y + dy} } }
		!(corners.map{|p| occupied?(p[:x], p[:y])}.include? false )
	end

	#	If the points within capture distance (not traveling through walls) include the prey's location, returns TRUE, else FALSE
	def players_within_distance?; captured_points.include? @prey.coords end

	#	The set of points within CAPTURE_DISTANCE euclidean units of distance from the hunter, without traveling through walls
	def captured_points(range = $capture_distance)
		checked_set = []
		current_set = [@hunter.coords]

		distance = 0
		# This collects every nonblocked point next to the current set of points (including diagonals) up to a certain number of moves
		until distance > range || current_set.empty?
			found_set = ((current_set.map{|c| collect_adjacent_points(c)}.flatten - checked_set) - current_set)
			checked_set += current_set
			current_set = found_set
			distance += 1
		end
		#	Take out any points that are outside the CAPTURE DISTANCE in euclidean distance from the hunter, and return the remaining set
		final_set = (checked_set + current_set).reject{|p| distance(@hunter.coords,p) > range}
	end

	#	Return true if the players are located in nonconnected subsets of the play space
	#	This should only be possible via a hunter placing a rule-breaking (ie enclosing) wall around either player
	def players_surrounded?
		return false if @walls.empty?
		a_star(@hunter.coords, @prey.coords)
	end

	#	Attempt to draw a path between the two players.
	#	Returns true if the players cannot reach one another, false if they can reach each other
	def a_star(start,goal)
		return false # TODO make this actually work
		###########################################
		checked = []
		options = [start]
		path = []
		g_score = Array.new($dimensions[:y], Array.new($dimensions[:x], Infinity))
		h_score = Array.new($dimensions[:y], Array.new($dimensions[:x], Infinity))
		f_score = Array.new($dimensions[:y], Array.new($dimensions[:x], Infinity))
		g_score[start[:y]][start[:x]] = 0
		h_score[start[:y]][start[:x]] = distance(start, goal, :diagonal)
		f_score[start[:y]][start[:x]] = h_score[start[:y]][start[:x]]
		until options.empty?
			option_scores = options.map{|o| f_score[o[:y]][o[:x]]}
			curr = options.delete_at option_scores.index(option_scores.min)
			puts curr
			return false if curr == goal
			checked << curr
			collect_adjacent_points(curr).each do |neighbor|
				next if checked.include? neighbor
				tentative_g_score = g_score[curr[:y]][curr[:x]] + 1 # 1 == dist_between(curr,neighbor)
				if !options.include? neighbor
					options << neighbor
					tentative_is_better = true
				elsif tentative_g_score < g_score[neighbor[:y]][neighbor[:x]]
					tentative_is_better = true
				else
					tentative_is_better = false
				end
				if tentative_is_better
					g_score[neighbor[:y]][neighbor[:x]] = tentative_g_score
					h_score[neighbor[:y]][neighbor[:x]] = distance(neighbor, goal)
					f_score[neighbor[:y]][neighbor[:x]] = g_score[neighbor[:y]][neighbor[:x]] + h_score[neighbor[:y]][neighbor[:x]]
				end
			end
		end
		true
	end

	#	Returns euclidean distance betweeen two points by default
	#	May be called with linear to find the distance taking only N,S,E, or W movements
	#	May be called with diagonal to find the larger of the two distances, horizontal and vertical
	def distance(start, goal, mode = :euclidean)
		if mode == :euclidean
			((start[:x] - goal[:x])**2 + (start[:y] - goal[:y])**2)**0.5
		elsif mode == :linear
			(start[:x] - goal[:x]).abs + (start[:y] - goal[:y]).abs
		elsif mode == :diagonal
			[(start[:x] - goal[:x]).abs, (start[:y] - goal[:y]).abs].max
		end
	end

	#	Given a point hash, collect all the non-blocked points adjacent horizontally, vertically, and diagonally one step from the point
	#	Note that points outside the board range, as well as the initial point, are not collected
	def collect_adjacent_points(coords)
		points = []
		x = coords[:x]
		y = coords[:y]
		x_range = ([0, x-1].max..[$dimensions[:x], x+1].min)
		y_range = ([0, y-1].max..[$dimensions[:y], y+1].min)
		x_range.each do |i|
			y_range.each do |j|
				points << {:x => i, :y => j} unless ( (i == x && j == y ) || occupied?(i, j))
			end
		end
		points
	end

	#	Saves the current state into the history (at index == turn number) and flips player and increments turn number
	def advance_turn!
		board_history << @board.clone
		@current_player = (@current_player == hunter ? @prey : @hunter)
		@current_turn += 1
	end

	#	Write the game results to the hunter, prey, and all spectators
	#	Note the explicit return to indicate that another method needs that hash as the return value from report_winner
	def report_winner
		if reason = won_by?(:hunter)
			puts "\n\nHunter (#{@hunter.username}) wins (#{reason}) at turn #{@current_turn}\n\n"
			@hunter.write("GAMEOVER #{current_round} WINNER HUNTER #{reason}")
			@prey.write("GAMEOVER #{current_round} LOSER PREY #{reason}")
			@spectators.each{|s| s.puts "GAMEOVER #{current_round} WINNER HUNTER #{reason}"}
			return {:winner => @hunter.username, :role => "Hunter", :time => current_round, :reason => reason}
		elsif reason = won_by?(:prey)
			puts "\n\Prey (#{@prey.username}) wins (#{reason}) at turn #{@current_turn}\n\n"
			@hunter.write("GAMEOVER #{current_round} LOSER HUNTER #{reason}")
			@prey.write("GAMEOVER #{current_round} WINNER PREY #{reason}")
			@spectators.each{|s| s.puts "GAMEOVER #{current_round} WINNER PREY #{reason}"}
			return {:winner => @prey.username, :role => "Prey", :time => current_round, :reason => reason}
		end
	end

	#	Disconnect all players
	def cleanup_players!; players.each{|p| p.disconnect} end

	#	Disconnect all spectators
	def cleanup_spectators!; @spectators.each{|s| p.close} end

	#	Helper method that returns array of [H, P]
	def players; [@hunter, @prey] end

	#	Given an X and Y coordinate, returns true if the point is out of the game bounds or has the value "wall", else false
	#	Note that this treats spaces occupied by prey and hunter as unoccupied
	def occupied?(x,y) #Returns true if the coordinate is in bounds and is occupied
		if (0...$dimensions[:x]).include?(x) && (0...$dimensions[:y]).include?(y)
			@board[y][x] == :wall
		else
			true
		end
	end

	#	Print the game board at full scale
	def print_board
		puts "GAME BOARD AT TIME: #{@current_turn}"
		print full_game_board.map{|c| c.join("")}.join("\n")
	end

	#	Print the game board with a reduction factor.
	#	For example, with a subsection_size of 10, every printed square is a 10x10 block from the actual game board
	def print_minified_board(subsection_size = 10)
		puts "\nMINIFIED GAME BOARD AT TIME: #{@current_turn}"
		mini_board = Array.new(($dimensions[:y]/subsection_size).ceil)
		mini_board.map!{|i| Array.new(($dimensions[:x]/subsection_size).ceil, ".")}
		#	Draw walls at their closest subsection
		@walls.each do |wall|
			wall.all_points.each do |p|
				mini_board[(p[:y]/subsection_size).floor][(p[:x]/subsection_size).floor] = 'X'
			end
		end
		#	Draw players at their closest subsection (this may overwrite walls and cause the appearance XXHXX)
		mini_board[@hunter.coords[:y]/subsection_size][@hunter.coords[:x]/subsection_size] = "H"
		mini_board[@prey.coords[:y]/subsection_size][@prey.coords[:x]/subsection_size] = "P"
		puts mini_board.map{|s| s.join("")}.join("\n")
	end

	#	Returns an array of X and . representing walls and open space, with the hunter's range displayed as -'s
	def full_game_board
		rows = []
		(0...$dimensions[:y]).each do |y|
			cols = []
			(0...$dimensions[:x]).each do |x|
				cols << board_status({:x => x, :y => y})
			end
			rows << cols
		end
		hunter_blob = captured_points
		hunter_blob.each do |point|
			rows[point[:y]][point[:x]] = "-" if rows[point[:y]][point[:x]] == '.'
		end
		rows
	end

	#	Returns the ASCII value used to represent the status of the board at the given coordinates
	def board_status(coords)
		if @hunter.coords == coords
			"H"
		elsif @prey.coords == coords
			"P"
		elsif @board[coords[:y]][coords[:x]] == :wall
			"X"
		else
			"."	# Note that this returns a . even on coordinates outside the board
		end
	end

	#	Checks the passed action and appropriately calls the wall-related method associated with it
	#	Returns false if the action is unrecognized, else returns the return value of the called method
	def change_wall(action, id, endpoints)
		if action == :add
			place_wall!(id, endpoints)
		elsif action == :remove
			remove_wall!(id)
		else
			false
		end
	end

	#	Add a wall to the game board if it can be places
	#	Returns true if it placed, false if it was invalid
	def place_wall!(id, endpoints)
		wall = Wall.new(id, endpoints)
		if can_place_wall? wall
			@walls << wall
			wall.all_points.each{|point| @board[point[:y]][point[:x]] = :wall }
			true
		else
			false
		end
	end

	#	Returns false if any of the points that would be taken by the wall are already occupied
	#	Returns false if the hunter has already placed their maximum number of walls
	def can_place_wall?(wall)
		return false if @walls.size >= $wall_max
		wall.all_points.each{|point| return false if occupied?(point[:x], point[:y]) }
		true
	end

	#	Find the wall with the passed ID and remove it
	#	Returns true if there was a wall with that ID, false if the ID was not found
	def remove_wall!(id)
		wall = @walls.select{|w| w.id == id}.first
		if wall
			wall.all_points.each{|point| @board[point[:y]][point[:x]] = :empty }
			@walls.delete(wall)
			true
		else
			false
		end
	end
end

#	Player superclass for both hunter and prey
class Player
	#	Class variable containing directions that bounces result in, keyed by _[current_direction][bounce_type]
	@@bounce_results = {:NW => { :vertical => :SW, :horizontal => :NE, :corner => :SE },
						:NE => { :vertical => :SE, :horizontal => :NW, :corner => :SW },
						:SW => { :vertical => :NW, :horizontal => :SE, :corner => :NE },
						:SE => { :vertical => :NE, :horizontal => :SW, :corner => :NW } }
	#	Class variable containing movement mappings into change in X and change in Y values, keyed on _[direction_of_travel]
	@@target_coords = {	# Directions for hunter and prey possible movements
						:NW => { :dx =>	-1, :dy => -1 },
						:NE => { :dx =>	+1, :dy => -1 },
						:SW => { :dx =>	-1, :dy => +1 },
						:SE => { :dx =>	+1, :dy => +1 },
						# Directions for prey-possible movements
						:N => { :dx =>	+0, :dy => -1 },
						:S => { :dx =>	+0, :dy => +1 },
						:E => { :dx =>	+1, :dy => +0 },
						:W => { :dx =>	-1, :dy => +0 } }

	attr_accessor :x, :y, :cooldown, :connection, :username, :game, :time_taken

	def initialize(game, connection, username, x, y)
		@game = game				# Pointer to the parent game
		@connection = connection
		@username = username
		place_at(x, y)				# Start the player at the passed coordinates
		@cooldown = 0				# Cooldown starts at 0
		@time_taken = 0
	end

	#	Close the connection to this player
	def disconnect; @connection.close end

	#	Returns a hash of the player's coordinates
	def coords; {:x => @x, :y => @y} end

	#	Get the next line of input from the player
	def read; @connection.readline end

	#	Write out TEXT to the player
	def write(text); @connection.puts(text) end

	#	Place the player at the passed location. The return value is the player's new coordinates
	#	Note, there are no error checks.
	def place_at(x, y)
		@x = x
		@y = y
		coords
	end

	#	Changes the player's direction according to bounce
	def bounce!; @direction = @@bounce_results[@direction][bounce_type] end

	#	Provides an alternate name for bounce_type to match methodname? returning boolean style
	def will_bounce?; bounce_type end

	#	Finds the bounce that the hunter will take, if any, given the current gamestate and direction of movement
	#	Returns false if no bounce is necessary
	def bounce_type
		dx = @@target_coords[@direction][:dx]
		dy = @@target_coords[@direction][:dy]
		if @game.occupied?(@x + dx, @y + dy)
			top_bottom = @game.occupied?(@x, @y + dy) # Detect for collision in N/S direction of movement
			left_right = @game.occupied?(@x + dx, @y) # Same for E/W
			if top_bottom && left_right # Both are collisions
				:corner
			elsif top_bottom && !left_right # Only vertical movement is collision
				:vertical
			elsif left_right && !top_bottom # Only horizontal movement is collision
				:horizontal
			else # Only the actual move itself is a collision
				:corner
			end
		else # Original movement was fine
			false
		end
	end
end

#	Hunter specific modifications to Player
class Hunter < Player
	attr_accessor :direction

	def initialize(game, connection, username)
		super(game, connection, username, $start_locations[:hunter][:x],$start_locations[:hunter][:y])
		write("ACCEPTED HUNTER")
		@direction = :SE
	end

	#	Returns H(X,Y,Cool,Dir)
	def to_state; "H(#{@x}, #{@y}, #{@cooldown}, #{@direction})" end

	#	Reads and turns hunter commands into valid command hashes
	#	Returns the command hash.
	#	Note that this is unforgiving and will interpret any input other than PASS as a move attempt and thus resets cooldown
	def get_command
		text = read.chomp
		command = {}
		if text =~ /PASS/i
			command[:pass] = true
		elsif text =~ /ADD\W+(\d+)\W+\((.*?)\),?\W+\((.*?)\)/i
			command[:action] = :add
			command[:id] = $1.to_i # FUTURE spec says it is 4 digits max
			command[:points] = [$2,$3].collect do |p|
				x,y = p.split(",")
				{:x => x.to_i, :y => y.to_i}
			end
		elsif text =~ /REMOVE\W+(\d+)/
			command[:action] = :remove
			command[:id] = $1.to_i # FUTURE spec says it is 4 digits max
		end
		command
	end

	#	Decrement the cooldown if necessary, place or remove any walls as necessary, and then bounce/move the hunter
	def take_turn
		if @cooldown > 0
			@cooldown -= 1
		else
			write game.game_state
			start_time = Time.now
			command = get_command
			@time_taken += Time.now - start_time
			# puts "Hunter - Time taken: #{@time_taken}"
			if !command[:pass]
				@cooldown = $cooldown[:hunter]
				@game.change_wall(command[:action], command[:id], command[:points])
			else
				#FUTURE passing case
			end
		end
		move! # The hunter will never not move
	end

	#	Bounce if necessary until a valid move is gound, then move the hunter along the appropriate diagonal
	def move!
		bounce! until !will_bounce? #TODO add surroundedness checking
		@x += @@target_coords[@direction][:dx]
		@y += @@target_coords[@direction][:dy]
	end
end

#	Hunter specific modifications to Player
class Prey < Player
	def initialize(game, connection, username)
		super(game, connection, username, $start_locations[:prey][:x],$start_locations[:prey][:y])
		write("ACCEPTED PREY")
	end

	#	Returns P(X,Y,Cool)
	def to_state; "P(#{@x}, #{@y}, #{@cooldown})" end

	#	Reads and turns prey commands into valid command hashes
	#	Returns the command hash.
	#	Note that this is unforgiving and will interpret any input other than PASS as a move attempt and thus resets cooldown
	def get_command
		text = read.chomp
		command = {}
		if text =~ /PASS/i
			command[:pass] = true
		elsif text =~ /(\d+),\W+(\d+)/i
			command[:x] = $1.to_i
			command[:y] = $2.to_i
		elsif text =~ /\A([NSEW]|[NS][EW])\z/i
			direction = $1.to_sym
			command[:x] = @x + @@target_coords[direction][:dx]
			command[:y] = @y + @@target_coords[direction][:dy]
		end
		command
	end

	#	Decrement the cooldown if necessary and then move the prey according to their command
	def take_turn
		if @cooldown > 0
			@cooldown -= 1
		else
			write game.game_state
			start_time = Time.now
			command = get_command
			@time_taken += Time.now - start_time
			if !command[:pass]
				@cooldown = $cooldown[:prey]
				if @game.occupied?(command[:x], command[:y])
					false #FUTURE invalid move case
				elsif (command[:x] - @x).abs > 1 || (command[:y] - @y).abs > 1
					false #FUTURE too large a move case
				else
					place_at(command[:x], command[:y])
				end
			else
				#FUTURE passing case
			end
		end
	end
end

#	Wall class :: fully defined by its ID and two endpoints
class Wall
	attr_accessor :id, :points, :orientation

	#	Note that orientation is derived and used entirely to make all_points easier
	def initialize(id, points)
		@id = id.to_i
		if points[0][:x] == points[1][:x]
			@points = points
			@orientation = :vertical
		elsif points[0][:y] == points[1][:y]
			@points = points
			@orientation = :horizontal
		else
			false #FUTURE non-flat wall sent
		end
	end

	#	Returns the set of all points between the two endpoints inclusive
	def all_points
		case @orientation
		when :vertical
			x = @points[0][:x]
			ys = [@points[0][:y],@points[1][:y]]
			(ys.min..ys.max).map{|y| {:x => x, :y => y}}
		when :horizontal
			xs = [@points[0][:x],@points[1][:x]]
			y = @points[0][:y]
			(xs.min..xs.max).map{|x| {:x => x, :y => y}}
		end
	end

	#	Returns (ID, X1, Y1, X2, Y2)
	def to_state; "(#{[@id, @points[0][:x], @points[0][:y], @points[1][:x], @points[1][:y]].join(", ")})" end
end

### Game execution ###

$threads = []
$start_locations = {
	:prey =>	{:x => 320,	:y => 200},
	:hunter =>	{:x => 0,	:y => 0}
}
$time_limit = 120
$capture_distance = 4
$dimensions = { :x => 500, :y => 500 }
$cooldown = { :hunter => 25, :prey => 1}
$wall_max = 6
$port = 23000

# Start the Server
server = EvasionServer.new
# Required to make the program wait for all threads to finish execution
$threads.each { |aThread|  aThread.join }
