Evasion game protocol
===

Connecting to the Gameserver
---
We will use access to host the server, connect to

	access#.cims.nyu.edu:23000
Exact host and port may change as necessary, parameterize if you wish

Joining a Game
---
To join a game, send the message

	JOIN _USERNAME_
where _USERNAME_ is any string < 40 characters containing no whitespace

The hunter is the first to join a game, the prey second
Upon joining a game, you will be welcomed with the message

	ACCEPTED _TYPE_
Where _TYPE_ is HUNTER or PREY

Game parameters
---
After both players join a game, the game begins with a parameters declaration of the form

	(xDimension, yDimension) wallCount, wallCooldown, preyCooldown
where the dimensions specify the size of the play area, wallCount is the maximum number of walls spawned by the hunter at once, wallCooldown is the number of turns between (exclusive) any use of the wall and the next turn it would be possible to, and preyCooldown being the number of turns between prey movements

For the game on November 15, 2010, these will be

	(500,500) _TBD_, _TBD25-50_, 1

Gamestate
---
If it is your turn, you will be sent a message with the current gamestate

	YOURTURN _ROUNDNUMBER_ H(x, y, cooldown, direction), P(x, y, cooldown), W[wall_one, wall_two]

Where W is delimited as an array [] containing a comma separated list of walls, each of which is of the form

	(id, x1, y1, x2, y2)

Game Over
---
Upon completion of the game, the winner is sent the message

	GAMEOVER _ROUNDNUMBER_ WINNER _ROLE_ _REASON_
where _ROLE_ is HUNTER or PREY and _REASON_ is EVADED, CAUGHT, TRAPPED, or TIMEOUT as appropriate

The loser is sent the message

	GAMEOVER _ROUNDNUMBER_ LOSER _ROLE_ _REASON_

Moves
===
*Note*: Any invalid move will cause no change in game state, though will activate the user's cooldown

Hunter
---
To do nothing and maintain ability ready state

	PASS
To add a new wall

	ADD _WALL_ID_ (x1, y1), (x2, y2)
where _WALL_ID_ is any 1-4 digit integer you specify
if you attempt to create a wall with an ID you've already used, creation will fail

To remove a wall

	REMOVE _WALL_ID_
*Note regarding walls*: The action of adding or removing a wall occurs before the hunter makes its automatic move. Therefore the hunter may place a wall and instantly use it to bounce itself
where the ID is an id you have already sent. If you remove a wall, you may reuse its ID

Prey
===
To do nothing and maintain ability ready state

	PASS
To move you may either specify a vector

	N | S | E | W | NW | NE | SE | SW
or may send the new coordinates

	X, Y

Rules
===

Capture Distance
---
The hunter has a capture radius of 4 spaces. This does not extend through walls.
Take a unit grid as a graph, drop out all points covered by walls in the game. Any location reachable by 4 unit-long traversals is within range. This means that the below is actually still a capture:

	X = wall, . = open, H = hunter, P = prey

	.....
	.HXP.
	..X..

Trapping
---
If at any point either the hunter or prey is completely separated from the other by walls, the PREY wins.

Bounce Rules
---

The hunter always moves diagonally. If move location is open, the hunter will make the move. This means the hunter can go from A to B even if both Xs are occupied:

	AX
	XB
The prey may also move through diagonal wall non-connections like the above.
There are two supertypes of collision:
*For all examples, assume H, hunter, is traveling NE*

Collision with symmetric walls

	.X
	H.

	XX
	HX

Collision occurs when H would attempt to move into the NE X
In both of the above cases, X has a new velocity of SW and ends the turn in the point one SW of the SW most point displayed

Collision with assymetry

	XX
	H.

	.X
	HX
Collision in this situation results in a change of velocity towards the open side
	The first changes to SE
	The second changes to NW

This can result in a second collision

	...	
	X.X
	.HX
			
Direction was changed to NW, but still created a collision
Direction rotates based on the new collision
Here it sees a symmetric collision to the NW, therefore taking SE

This leads to either a move or

	...
	X.X
	.HX
	..X
				
	Wow.
But now we have an assymetric collision with the SE
And thus end up pointed back at SW, and ending SW.
If SW were blocked, then notice that every corner is blocked, and the hunter has trapped themself. As the only way to get in this situation is to run into a setup of 2+ walls, and the only way to trap yourself in requires a third wall, that means that the move was intentional and pretty boneheaded. If the hunter is trapped, they also have a full cooldown remaining. Given that, it seems fair that this results in an instant prey-win.
