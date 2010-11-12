require 'socket'

class Evasion
	attr_accessor :server, :hunter, :prey, :board, :board_history, :walls, :current_player, :current_turn
	def initialize
		start_server!
		setup_board!
		setup_players!
		@board_history = []
		@walls = []
	end

	### Methods called by the game setting itself up or by .play

	def start_server!
		@server = TCPServer.open($port)
	end

	def setup_board!
		@board = Array.new($dimensions[:y]){ Array.new($dimensions[:x]) {:empty} } #Remember, this is rows of Y, columns of X, thus ary[y][x]
	end

	def setup_players!
		@hunter = Hunter.new(self, @server.accept)
		@prey = Prey.new(self, @server.accept)
	end

	def play
		@current_turn = 0
		@current_player = @hunter
		players.each{|p| p.write(game_parameters)}
		until is_game_over?
			@current_player.take_turn
			advance_turn!
		end
		report_winner
		cleanup_players!
	end

	def game_parameters
		"(#{$dimensions[:x]}, #{$dimensions[:y]}) #{$wall_max}, #{$cooldown[:hunter]}, #{$cooldown[:prey]}"
	end

	def game_state
		"YOURTURN #{self.current_round} #{@hunter.to_state}, #{@prey.to_state}, W[#{@walls.map{|w| w.to_state}.join(", ")}]"
	end

	def current_round
		(@current_turn / 2).floor
	end

	def is_game_over?
		won_by?(:hunter) || won_by?(:prey)
	end

	def won_by?(player) #Returns false or string with reason
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
			elsif @hunter.time_taken > $time_limit
				"TIMEOUT"
			else
				false
			end
		end
	end

	def players_within_distance?
		checked_set = []
		current_set = [@hunter.coords]

		distance = 0
		until distance > $capture_distance || current_set.empty?
			found_set = (current_set.map{|c| collect_adjacent_points(c)} - checked_set) - current_set
			checked_set += current_set
			current_set = found_set
			distance += 1
		end

		h_x = @hunter.x
		h_y = @hunter.y
		final_set = (checked_set + current_set).reject{|p| ((p[:x] - h_x)**2 + (p[:y] - h_y)**2)**(0.5) > $capture_distance}
		final_set.include? @prey.coords
	end

	def players_surrounded?
		checked_set = []
		current_set = [@prey.coords]
		until current_set.empty? #Expand until there is nowhere to expand into
			found_set = (current_set.map{|c| collect_adjacent_points(c)} - checked_set) - current_set
			return false if found_set.include? @prey.coords
			checked_set += current_set
			current_set = found_set
		end
		final_set.include? @prey.coords #Redundant with the earlier return false, but done so in case my expand-from-hunter algorithm has a bug
	end

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

	def advance_turn!
		board_history << @board.clone
		@current_player = (@current_player == hunter ? @prey : @hunter)
		@current_turn += 1
	end

	def report_winner
		if reason = won_by?(:hunter)
			@hunter.write("GAMEOVER #{current_round} WINNER HUNTER #{reason}")
			@prey.write("GAMEOVER #{current_round} LOSER PREY #{reason}")
		elsif reason = won_by?(:prey)
			@hunter.write("GAMEOVER #{current_round} LOSER HUNTER #{reason}")
			@prey.write("GAMEOVER #{current_round} WINNER PREY #{reason}")
		end
	end

	def cleanup_players!
		players.each{|p| p.disconnect}
	end

	def players
		[@hunter, @prey]
	end

	def occupied?(x,y) #Returns true if the coordinate is in bounds and is occupied
		if (0...$dimensions[:x]).include?(x) && (0...$dimensions[:y]).include?(y)
			@board[y][x] == :wall
		else
			true
		end
	end

	### Methods called by wall interactions ###

	def change_wall(action, id, endpoints) #True if wall created or deleted correctly
		if action == :place
			place_wall!(id, endpoints)
		elsif action == :remove
			remove_wall!(id)
		else
			false
		end
	end

	def place_wall!(id, endpoints) #True if wall is created
		wall = Wall.new(id, endpoints)
		if can_place_wall? wall
			@walls << wall
			wall.all_points.each{|point| @board[point[:y]][point[:x]] = :wall }
			true
		else
			false
		end
	end

	def can_place_wall?(wall)
		return false if @walls.size > $wall_max
		wall.points.each{|point| return false if occupied?(point[:x], point[:y]) }
		true
	end

	def remove_wall!(id) #True if wall is found for deletion
		wall = @walls.select{|w| w.id == id}
		if wall
			wall.points.each{|point| @board[point[:y]][point[:x]] = :empty }
			@walls.delete(wall)
			true
		else
			false
		end
	end
end

class Player
	@@bounce_results = {:NW => { :vertical => :SW, :horizontal => :NE, :corner => :SE },
						:NE => { :vertical => :SE, :horizontal => :NW, :corner => :SW },
						:SW => { :vertical => :NW, :horizontal => :SE, :corner => :NE },
						:SE => { :vertical => :NE, :horizontal => :SW, :corner => :NW } }

	@@target_coords = {	#Directions for hunter and prey possible movements
						:NW => { :dx =>	-1, :dy => -1 },
						:NE => { :dx =>	+1, :dy => -1 },
						:SW => { :dx =>	-1, :dy => +1 },
						:SE => { :dx =>	+1, :dy => +1 },
						#Directions for prey-possible movements
						:N => { :dx =>	+0, :dy => -1 },
						:S => { :dx =>	+0, :dy => +1 },
						:E => { :dx =>	+1, :dy => +0 },
						:W => { :dx =>	-1, :dy => +0 } }

	attr_accessor :x, :y, :cooldown, :connection, :username, :game, :time_taken

	def initialize(connection, game, x, y)
		@game = game
		@connection = connection
		place_at(x, y)
		@cooldown = 0
		@time_taken = 0
	end

	def disconnect
		@connection.close
	end

	def coords
		{:x => @x, :y => @y}
	end

	def read
		@connection.readline
	end

	def write(text)
		@connection.puts(text)
	end

	def place_at(x, y)
		@x = x
		@y = y
	end

	def bounce!	#Complete direction flip if hitting a corner, else reflection
		@direction = @@bounce_results[@direction][bounce_type]
	end

	def will_bounce?
		bounce_type
	end

	def bounce_type #Allows a player to squeeze through a diagonal space
		dx = @@target_coords[@direction][:dx]
		dy = @@target_coords[@direction][:dy]
		if @game.occupied?(@x + dx, @y + dy)
			top_bottom = @game.occupied?(@x, @y + dy) #Detect for collision in N/S direction of movement
			left_right = @game.occupied?(@x + dx, @y) #Same for E/W
			if top_bottom && left_right #Both are collisions
				:corner
			elsif top_bottom && !left_right #Only vertical movement is collision
				:vertical
			elsif left_right && !top_bottom #Only horizontal movement is collision
				:horizontal
			else #Only the actual move itself is a collision
				:corner
			end
		else #Original movement was fine
			false
		end
	end
end

class Hunter < Player
	attr_accessor :direction
	def initialize(game, connection)
		super(game, connection, 0,0)
		write("ACCEPTED HUNTER")
		@direction = :SE
	end

	def to_s
		"H(#{@x}, #{@y}, #{@cooldown}, #{@direction})"
	end

	def get_command
		text = read.chomp
		command = {}
		if text =~ /PASS/i
			command[:pass] = true
		elsif text =~ /ADD\W+(\d+)\W+\((.*?)\)W+\((.*?)\)/i
			command[:action] = :add
			command[:id] = $1.to_i #FUTURE spec says it is 4 digits max
			command[:points] = [$2,$3].collect do |p|
				x,y = p.split(",").map(&:to_i)
				{:x => x, :y => y}
			end
		elsif text =~ /REMOVE\W+(\d+)/
			command[:action] = :remove
			command[:id] = $1.to_i #FUTURE spec says it is 4 digits max
		end
		command
	end

	def take_turn
		if @cooldown > 0
			@cooldown -= 1
		else
			start_time = Time.now
			command = get_command
			@time_taken += Time.now - start_time
			if !command[:pass]
				@cooldown = $wall_cooldown
				@game.change_wall(command[:action], command[:id], command[:points])
			else
				#FUTURE passing case
			end
		end
		move! #Note: Moves in both cases, and move takes place after all wall changes in a turn
	end

	def move!
		bounce! until !will_bounce? #TODO add surroundedness checking
		@x += @game.target_coords[@direction][:dx]
		@y += @game.target_coords[@direction][:dy]
	end
end

class Prey < Player
	def initialize(game, connection)
		super(game, connection, 330,200)
		write("ACCEPTED PREY")
	end

	def to_s
		"P(#{@x}, #{@y}, #{@cooldown})"
	end

	def get_command
		text = read.chomp
		command = {}
		if text =~ /PASS/i
			command[:pass] = true
		elsif text =~ /\((\d+),\W+(\d+)\)/i
			command[:x] = $1.to_i
			command[:y] = $2.to_i
		elsif text =~ /([NSEW]|[NS][EW])/i
			direction = $1.to_sym
			command[:x] = @x + @game.target_coords[direction][:dx]
			command[:y] = @y + @game.target_coords[direction][:dy]
		end
		command
	end

	def take_turn
		if @cooldown > 0
			@cooldown -= 1
		else
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

class Wall
	attr_accessor :id, :points, :orientation
	def initialize(id, points)
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

	def to_state
		"(#{[@id, @points[0][:x], @points[0][:y], @points[1][:x], @points[1][:y]].join(", ")})"
	end
end

### Game execution ###
$time_limit = 120
$capture_distance = 4
$dimensions = { :x => 500, :y => 500 }
$cooldown = { :hunter => 25, :prey => 1}
$wall_max = 6
$port = 23000
game = Evasion.new
game.play
