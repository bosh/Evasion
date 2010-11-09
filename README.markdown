




>JOIN _USERNAME_
ACCEPTED HUNTER|PREY
PARAMETERS (xDim,yDim), wallCount, wallCooldown, preyCooldown

GAMESTATE _ROUNDNUMBER_ H(x, y, cooldown, vector), P(x, y, cooldown), W[(id, x1, y1, x2, y2), ...]
YOURTURN

if winner
	GAMEOVER _ROUNDNUMBER_ WINNER H|P CAUGHT|EVADED || TIMEOUT
if loser
	GAMEOVER _ROUNDNUMBER_ LOSER H|P EVADED|CAUGHT || TIMEOUT

hunter possible messages
>PASS
	OKAY
>ADD \d+ (X1, Y1), (X2, Y2)
	SUCCESS/FAIL
>REMOVE \d+
	SUCCESS/FAIL

prey possible messages
>x,y
	SUCCESS/FAIL
>N,S,E,W, or any combo of [NS][EW]
	SUCCESS/FAIL
>HOLD
	OKAY
