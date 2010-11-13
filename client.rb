require 'socket'	# Sockets are in standard library

hostname = 'localhost'
port = 23000

s = TCPSocket.open(hostname, port)

accepted = false
game_on = false
while line = s.gets	# Read lines from the socket
	puts line.chop	# And print with platform line terminator
	if game_on
		s.puts gets()
	end	
	game_on = true if accepted
	accepted = true if line =~ /ACCEPTED/i
end

s.close				# Close the socket when done
