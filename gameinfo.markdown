Evasion

H (the Hunter) wants to catch P (the prey). P wants to evade H as long as possible. You will play both roles (i.e. in the competition, once you will be the hunter and once the prey).

The game is played on a 500 by 500 square. Both P and H bounce off the sides (perfect reflection -- angle in equals angle out) and bounce off any walls created by H.

P is initially at point (330, 200) and H at position (0,0). In a time step, H moves one unit (always diagonally or counter-diagonally based on its bounce history). P moves only every other time step. It moves in its current direction unless it hits a wall or it decides to move in some other direction (or it chooses not to move). The only illegal move is for it to try to move through a wall. If P tries to move through a wall, it is not allowed to do so. H may create a wall not more frequently than every 10 time steps. The wall must be vertical or horizontal. Provided the wall does not touch another wall, H, or P. the wall is created instantly. If the proviso is not met, the wall is not created, H is informed, and H must wait at least 10 time steps before attempting to create another wall.

H catches P if H is within four units of P (based on Euclidean distance) and there is no wall between them. H's score is the number of time units it takes to catch P. Less is better.
Architect

The architect will provide a graphical display showing the walls and the movements of H and P. The architect reports the positions of H to P and to P of H and also the position of all walls. The architect also records the score and determines if it is impossible for H to find P. The graphics should show the positions of H and P, the walls, and the current time. 