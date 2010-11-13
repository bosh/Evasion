require 'socket'	# Sockets are in standard library

hostname = 'localhost'
port = 23000

s = TCPSocket.open(hostname, port)

game_on = false
while line = s.gets	# Read lines from the socket
	puts line.chop	# And print with platform line terminator
	game_on = true if line =~ /ACCEPTED/i
	if game_on
		s.puts gets()
	end	
end

s.close				# Close the socket when done
