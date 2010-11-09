require 'socket'               # Get sockets from stdlib
server = TCPServer.open(23000)  # Socket to listen on port 2000

clients = []
clients << hunter = server.accept       # Wait for a client to connect
hunter.puts(Time.now.ctime)  # Send the time to the client
clients << prey = server.accept
prey.puts(Time.now.ctime)  # Send the time to the client

clients.each{|c| c.puts "Closing"}
clients.each{|c| c.close}