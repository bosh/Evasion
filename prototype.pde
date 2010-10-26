int currentindex = 0;
int numx = 1;
int numy = 1;
int dirx = 1;
int diry = 1;
int oldmouseX = -1;
int oldmouseY = -1;
int[] beginX = new int[200];
int[] endX = new int[200];
int[] beginY = new int[200];
int[] endY = new int[200];
int oldKeyCode = -1;

void setup() {
	size(500, 500);
	background(255);
	int i = 0;
	while(i < 200){
		beginX[i] = -1;
		beginY[i] = -1;
		endX[i] = -1;
		endY[i] = -1;
		i+= 1;
	}
}

// redraw all lines recorded in the vectors
void redrawlines() {
	int j = 0;
	while(j < currentindex){
		line(beginX[j], beginY[j], endX[j], endY[j]);
		j+= 1;
	}
}

void keyPressed() {
	if ((key == CODED) && (keyCode != oldKeyCode)) {
		if (keyCode == UP) {
			print(" Just pressed key up ");
		} else if (keyCode == DOWN) {
			print(" Just pressed key down ");
		} else if (keyCode == LEFT) {
			print(" Just pressed key left ");
		} else if (keyCode == RIGHT) {
			print(" Just pressed key right ");
		}
	oldKeyCode = keyCode;
	}
}

void draw() {
	stroke(0);
	keyPressed();
	if(mousePressed) {
		if(oldmouseX != - 1) {
			if(abs(oldmouseX - mouseX) > abs(oldmouseY - mouseY)) {
				if(currentindex < 200) {
					line(mouseX, oldmouseY, oldmouseX, oldmouseY);
					beginX[currentindex] = mouseX;
					beginY[currentindex] = oldmouseY;
					endX[currentindex] = oldmouseX;
					endY[currentindex] = oldmouseY;
					currentindex+= 1;
				}
			} else { // y difference greater than x difference
				if(currentindex < 200){
					if(mouseY != oldmouseY){
						line(oldmouseX, mouseY, oldmouseX, oldmouseY);
						beginX[currentindex] = oldmouseX;
						beginY[currentindex] = mouseY;
						endX[currentindex] = oldmouseX;
						endY[currentindex] = oldmouseY;
						currentindex+= 1;
					}
				}// and then what? TYLER
			}
		}
		// print(" jacked " + mouseX);
		// print(" oldmouseX is " +oldmouseX);
		oldmouseX = mouseX;
		oldmouseY = mouseY;
	}
	{ //  advance ball and then check whether we hit a line
		numx+= dirx;
		numy+= diry;
		background(255); // refreshes the screen
		int i = 1;
		set(numx, (int) ((numy)), color(i));
		set(numx, (int) (1+(numy)), color(i));
		set(numx, (int) ((-1)+(numy)), color(i));
		set(numx+1, (int) ((numy)), color(i));
		set(numx-1, (int) ((numy)), color(i));
		set(numx+1, (int) (1+(numy)), color(i));
		set(numx-1, (int) ((-1)+(numy)), color(i));
		set(numx+1, (int) ((numy)-1), color(i));
		set(numx-1, (int) ((numy)+1), color(i));
		// now determine whether we hit a line and if so, change direction
		int j = 0;
		while(j < currentindex) {
			if(((beginX[j] == endX[j]) && (numx == beginX[j])) && (((((endY[j]) >= beginY[j]) && ((endY[j] >= numy) && (beginY[j] <= numy)))) || (((endY[j]) <= beginY[j]) && ((endY[j] <= numy) && (beginY[j] >= numy))))) {
				dirx = - dirx;
			}
			if(((beginY[j] == endY[j]) && (numy == beginY[j]))&& (((((endX[j]) >= beginX[j]) && ((endX[j] >= numx) && (beginX[j] <= numx)))) ||(((endX[j]) <= beginX[j]) && ((endX[j] <= numx) && (beginX[j] >= numx))))) {
				diry = - diry;
			}
			j+= 1;
		}
		if((numx > 501) || (numx < -1)) {
			dirx = - dirx;
		}
		if((numy > 501) || (numy < -1)) {
			diry = - diry;
		}
		redrawlines();
		// print(" currentindex is " + currentindex);
	}
}