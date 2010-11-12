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
		players.each{|p| p.respond(game_parameters)}
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
		"YOURTURN #{current_round} #{@hunter.to_state}, #{@prey.to_state}, W[{@walls.map{|w| w.to_state}.join(", ")}]"
	end

	def current_round
		(@current_turn / 2).floor
	end

	def is_game_over?
		won_by?(:hunter) || won_by?(:prey)
	end

	def won_by?(player)
		case player
		when :hunter
			#TODO
			false
		when :prey
			#TODO
			false
		end
	end

	def advance_turn!
		board_history << @board.clone
		@current_player = (@current_player == hunter ? @prey : @hunter)
		@current_turn += 1
	end

	def report_winner
		if won_by?(:hunter)
			@hunter.respond("CAUGHT: #{@current_turn}")
			@prey.respond("CAUGHT: #{@current_turn}")
		elsif won_by?(:prey)
			@hunter.respond("ESCAPED: #{@current_turn}")
			@prey.respond("ESCAPED: #{@current_turn}")
		end
	end

	def cleanup_players!
		players.each{|p| p.disconnect}
	end

	def players
		[@hunter, @prey]
	end

	### Methods called by players on their @game ###

	def occupied?(x,y) #Returns true if the coordinate is in bounds and is empty
		if (0...$dimensions[:x]).include?(x) && (0...$dimensions[:y]).include?(y)
			@board[y][x] == :empty
		else
			false
		end
	end

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

	attr_accessor :x, :y, :cooldown, :connection, :username, :game

	def initialize(connection, game, x, y)
		@game = game
		@connection = connection
		place_at(x, y)
		@cooldown = 0
	end

	def disconnect
		@connection.close
	end

	def get_input
		#TODO connection.gets until something interesting (so you can always assume a valid return from get_input)
	end

	def respond(text)
		#TODO connection.write(text)
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
		respond("ACCEPTED HUNTER")
		@direction = :SE
	end

	def to_s
		"H(#{@x}, #{@y}, #{@cooldown}, #{@direction})"
	end

	def take_turn
		if @cooldown > 0
			@cooldown -= 1
		else
			command = get_input
			if @game.change_wall(command[:action], command[:id], command[:points])
				@cooldown = $wall_cooldown
			else
				#TODO failed action case
			end
		end
		move!
	end

	def move!
		bounce! until !will_bounce?
		dx = @game.target_coords[@direction][:dx]]
		dy = @game.target_coords[@direction][:dy]]
		@x += dx
		@y += dy
	end
end

class Prey < Player
	def initialize(game, connection)
		super(game, connection, 330,200)
		respond("ACCEPTED PREY")
		@direction = nil
	end

	def to_s
		"P(#{@x}, #{@y}, #{@cooldown})"
	end

	def get_input
		#TODO read until a parseable move is sent
	end

	def take_turn
		if @cooldown > 0
			@cooldown -= 1
		else
			command = get_input
			if @game.occupied?(command[:x], command[:y])
				#TODO invalid move case
			elsif (command[:x] - @x).abs > 1 || (command[:y] - @y).abs > 1
				#TODO too large a move case
			else
				place_at(command[:x], command[:y])
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
			#TODO non-flat wall sent
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

$dimensions = { :x => 500, :y => 500 }
$cooldown = { :hunter => 25, :prey => 1}
$wall_max = 6
$port = 23000
game = Evasion.new
game.play
