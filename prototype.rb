class Evasion
	attr_accessor :server, :hunter, :prey, :board, :board_history, :walls, :current_player, :current_turn
	def initialize
		start_server
		setup_board!
		setup_players!
		@board_history = []
		@walls = []
	end

	def start_server
		#TODO open server at $port
	end

	def setup_board!
		@board = Array.new(500){ Array.new(500) {:empty} }
	end

	def setup_players!
		@hunter = Hunter.new
		@prey = Prey.new
	end

	def cleanup_players!
		@hunter.disconnect
		@prey.disconnect
	end

	def play
		@current_turn = 0
		until is_game_over?
			@current_player.take_turn
			advance_turn!
		end
		if won_by?(:hunter)
			@hunter.respond("CAUGHT: #{@current_turn}")
			@prey.respond("CAUGHT: #{@current_turn}")
		elsif won_by?(:prey)
			@hunter.respond("ESCAPED: #{@current_turn}")
			@prey.respond("ESCAPED: #{@current_turn}")
		end
		cleanup_players!		
	end

	def advance_turn!
		board_history << @board.clone
		@current_player = (@current_player == hunter ? @prey : @hunter)
		@current_turn += 1
	end

	def occupied?(x,y) #Returns true if the coordinate is in bounds and is empty
		if ($boundaries[:x][:min]..$boundaries[:x][:max]).include? x && ($boundaries[:y][:min]..$boundaries[:y][:max]).include? y
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
		wall.points.each{|point| return false if occupied?(point[:x], point[:x]) }
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

	def state
		"#{@current_turn}: #{@current_player.to_s}\nHunter: #{@hunter.to_s}\nPrey: #{@prey.to_s}\n#{@walls.map(&:to_s).join(" ")}"
	end
end

class Player
	attr_accessor :x, :y, :direction, :cooldown, :connection
	def initialize(x, y)
		@connection = connect
		place_at(x, y)
		@cooldown = 0
	end

	def connect
		#TODO wait for first connection
	end

	def disconnect
		#TODO connection.close
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
		bounce_results = {
			:NW => { :top =>	:SW, :left 	=> :NE, :corner => :SE },
			:NE => { :top =>	:SE, :right => :NW, :corner => :SW },
			:SW => { :bottom => :NW, :left 	=> :SE, :corner => :NE },
			:SE => { :bottom => :NE, :right => :SW, :corner => :NW }
		}
		@direction = bounce_results[@direction][bounce_direction]
	end

	def will_bounce?
		bounce_direction
	end

	def bounce_direction #Allows a player to squeeze through a diagonal space
		case @direction
		when :NW
			if $game.occupied?(@x - 1, @y - 1)
				if $game.occupied?(@x - 1, @y)
					:left
				elsif $game.occupied?(@x, @y - 1)
					:top
				else
					:corner
				end
			else
				false
			end
		when :NE
			if $game.occupied?(@x + 1, @y - 1)
				if $game.occupied?(@x + 1, @y)
					:right
				elsif $game.occupied?(@x, @y - 1)
					:top
				else
					:corner
				end
			else
				false
			end
		when :SE
			if $game.occupied?(@x + 1, @y + 1)
				if $game.occupied?(@x + 1, @y)
					:right
				elsif $game.occupied?(@x, @y + 1)
					:bottom
				else
					:corner
				end
			else
				false
			end
		when :SW
			if $game.occupied?(@x - 1, @y + 1)
				if $game.occupied?(@x - 1, @y)
					:left
				elsif $game.occupied?(@x, @y + 1)
					:bottom
				else
					:corner
				end
			else
				false
			end
		else
			false
		end
	end

	def to_s
		"(#{@x},#{@y}) #{@cooldown}"
	end
end

class Hunter < Player
	attr_accessor :cooldown
	def initialize
		super(0,0)
		@direction = :SE
	end

	def take_turn
		if @cooldown > 0
			@cooldown -= 1
		else
			command = get_input
			if $game.change_wall(command[:action], command[:id], command[:points])
				@cooldown = $wall_cooldown
			else
				#TODO failed action case
			end
		end
		move!
	end

	def move!
		bounce! until !will_bounce?
		case @direction
			when :NW
				@x -= 1
				@y -= 1
			when :NE
				@x += 1
				@y -= 1
			when :SE
				@x += 1
				@y += 1
			when :SW
				@x -= 1
				@y += 1
		end
	end
end

class Prey < Player
	def initialize
		super(330,200)
		@direction = nil
	end

	def get_input
		#TODO read until a parseable move is sent
	end

	def take_turn
		if @cooldown > 0
			@cooldown -= 1
		else
			command = get_input
			if $game.occupied?(command[:x], command[:y])
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

	def to_s
		"[" + @id.to_s + " " + @points.map{|p| "(#{p[:x]}#{p[:y]})"}.join(", ") + "]"
	end
end

### Game execution ###

$boundaries = { :x => { :min => 0, :max => 499 },
				:y => { :min => 0, :max => 499 } }
$wall_cooldown = 10
$wall_max = 6
$port = 23000
$game = Evasion.new
$game.play