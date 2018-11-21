// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 128                  //image height
#define  IMWD 16                  //image width (divided by 8 due to compression)
#define  maxCycles 100

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0]: port p_scl = XS1_PORT_1E;         //interface ports to orientation
on tile[0]: port p_sda = XS1_PORT_1F;
on tile[0]: in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[1]: out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

enum { Black = 0x00, White = 0xFF };

//DISPLAYS an LED pattern
int showLEDs(out port p, chanend fromDist) {
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
  int lighting = 1;
  while (lighting) {
    fromDist:> pattern;   //receive new pattern from distributor
    if (pattern == 0) lighting = 0;
    p <: pattern;
  }
  return 0;
}

//READ BUTTONS and send button pattern to distributor
void buttonListener(in port b, chanend toDist) {
  int r, listening = 1, started = 0;
  while (listening) {
    /printf("Start\n");/
    // At first, wait for the user to press the start button
    if (!started) {
      b when pinseq(15)  :> r;    // check that no button is pressed
      b when pinsneq(15) :> r;    // check if some buttons are pressed
      if (r==14) {
        started = 1;
        toDist <: r;
      }
    }
    else {
      toDist :> listening;
      b :> r;
      // Tell the distributor whether or not a button is pressed
      toDist <: r;
      if (r != 15) b when pinseq(15)  :> r;  // Wait to avoid repeating for the same press
    }
    /printf("End\n");/
  }
}

int pow(int x, int y) {
  int a = x;
  for (int i = 1; i < y; i++) {
    a *= x;
  }
  return a;
}

int toBits(int x) {
  int bits = 0;
  for (int n = 0; n < 8; n++) {
    int a = pow(10, n);
    bits += ((x >> n) & 1) * a;
  }
  return bits;
}

// Sum the first n elements of the array, and
long long sum(const long long arr[], int n) {
  long long total = 0;
  for (int x = 0; x < n; x++) {
    total += arr[x];
    /printf("%lli %lli\n", arr[x], total);/
  }
  /printf("%d elements. 3rd is %lli, suggesting %lli total. Real total is %lli.\n", n, arr[2], (arr[2]*n), total);/
  return total;
}

// Find the index of the largest element of the first n elements of the array
int largest(const long long arr[], int n) {
  int index = 0;
  long long max = 0;
  for (int x = 0; x < n; x++) {
    if (arr[x] > max) {
      max = arr[x];
      index = x;
    }
  }
  return index;
}

// Find the value of the largest element of the first n elements of the array
long long max(const long long arr[], int n) {
  long long max = 0;
  for (int x = 0; x < n; x++) {
    if (arr[x] > max) {
      max = arr[x];
    }
  }
  return max;
}

//WAIT function
void waitMoment() {
  timer tmr;
  int waitTime;
  tmr :> waitTime;                       //read current timer value
  waitTime += 20000000;                  //set waitTime to 0.2s after value
  tmr when timerafter(waitTime) :> void; //wait until waitTime is reached
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend toDist1, chanend toDist2) {
  int res;
  long long startTime, endTime;
  long long timings[IMHT];
  timer tmr;
  uchar line[ (IMWD*8) ];
  toDist1 :> int start;
  printf( "DataInStream: Start...\n" );
  //Open PGM file
  res = _openinpgm( infname, (IMWD*8), IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }
  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    tmr :> startTime;
    _readinline( line, (IMWD*8) );
    for( int x = 0; x < (IMWD*8); x += 8 ) {
      // Compress the uchars to 1/8th size...
      uchar chunk = 0;
      for (int n = 0; n < 8; n++) {
        if (line[x+n] == White) chunk += 1 << (7 - n);
      }
      if ((y < IMHT/2 + 1) || (y == IMHT - 1)) toDist1 <: chunk;
      if ((y == 0) || (y >= IMHT/2 -1)) toDist2 <: chunk;
      /printf( "-%08d ", toBits(chunk) ); //show image values as chunks/
    }
    tmr :> endTime;
    // The timer overflows after 4294967295, so we need to fix the case where it may overflow between lines.
    if (endTime > startTime) timings[y] = endTime - startTime;
    else {
      timings[y] = (4294967295 - startTime) + endTime; // (time before overflow) + (time after overflow)
      printf("Timer overflow: %lli to %lli.\n", startTime, endTime);
    }
    /printf( "\n" );/
  }

  for (int x = 0; x < IMHT; x++) printf("%li\n", timings[x]);
  //Close PGM image file
  _closeinpgm();
  printf("Input took %f seconds.\n", ((float)sum(timings, IMHT)/100000000));
  printf( "DataInStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////



// Given an image array and a particular cell cooridinate, enumerate the live neighbours
int count(const uchar img[ IMWD ][IMHT/2 + 2], int x,  int y) {
  int count = 0, a, b;
  for (int j = y - 1; j < y + 2; j++) {
    if (j == -1) b = IMHT/2 + 1;
    else b = j;
    for (int i = x - 1; i < x + 2; i++) {
      if (!((i == x) && (j == y))) { // Don't check the cell we are searching around
        if (i == -1) a = (IMWD*8) - 1;
        else if (i == (IMWD*8)) a = 0;
        else a = i;
        div_t split = div(a, 8);
        /printf("Searching at (%d, %d).\n");/
        /printf("The cell is %d.\n", a, b, ((img[split.quot][b] >> (7 - split.rem)) & 1));/
        /waitMoment();/
        count += (img[split.quot][b] >> (7 - split.rem)) & 1;
      }
    }
  }
  /if ((x == 4) && (y == 5)) printf("Cell (%d, %d) has %d surrounding live cells.\n", x, y, count);/
  return count;
}

// Find the total number of live cells in a half image
int total(uchar img[ IMWD ][IMHT/2 + 2]) {
  int total = 0;
  for (int y = 0; y < (IMHT/2); y++) {
    for (int x = 0; x < IMWD; x++) {
      for (int n = 0; n < 8; n++) {
        total += ((img[x][y] >> n) & 1);
      }
    }
  }
  return total;
}


// Worker thread to process a section of the image. Takes the image, a starting cooridinate, a finishing cooridinate and a channel
// and works on the section inbetween, sending the results to distributor without storing them.
void worker(const uchar img[ IMWD ][IMHT/2 + 2], int xStart, int yStart, int xEnd, int yEnd, chanend toGath) {
  for( int y = yStart; y < yEnd; y++ ) {
    for( int x = xStart; x < xEnd; x++ ) {
      int newChunk = 0;
      int oldChunk = img[x][y];
      // Build the chunk from each cell
      for (int n = 0; n < 8; n++) {
        // Count the number of live neighbours
        int liveNeighbours = count(img, (x*8 + n), y);
        // Kill, revive, or leave the cell, within the chunk
        if ((oldChunk >> 7-n) & 1) {
          if ((liveNeighbours == 2) || (liveNeighbours == 3)) {
            /printf("Cell at (%d, %d) has %d neighbours, survives.\n", (x*8 + n), y, liveNeighbours);/
            newChunk += (1 << 7-n);
          }
        }
        else {
          if (liveNeighbours == 3) {
            /printf("Cell at (%d, %d) has %d neighbours, comes alive.\n", (x*8 + n), y, liveNeighbours);/
            newChunk += (1 << 7-n);
          }
        }
        /if (liveNeighbours) printf("Cell at (%d, %d) has %d neighbours.\n", (x*8 + n), y, liveNeighbours);/
      }
      /printf("New chunk is %08d\n", toBits(newChunk));/
      toGath <: (uchar)newChunk;
    }
  }
}

// Receive the new pixels from the workers and write them to the appropriate locations in the new image.
// gatherer now assumes that it works on an image of IMHT/2 + 2 size, and ignores the last 2 lines
void gatherer(uchar newImg[ IMWD ][IMHT/2 + 2], chanend fromWorker1, chanend fromWorker2, chanend fromWorker3, chanend fromWorker4){
  int sectionsDone = 0;
  int x1 = 0, y1 = 0, x2 = (IMWD/2), y2 = 0, x3 = 0, y3 = (IMHT/4), x4 = (IMWD/2), y4 = (IMHT/4); // Counters for each worker
  while (sectionsDone < 4) {
    select {
      case fromWorker1 :> newImg[x1][y1]:
        if ((x1 + 1) < (IMWD/2)) x1++; // Iterate along the line for each worker until the line end
        else {
          x1 = 0;
          y1++;
        }
        if (y1 == (IMHT/4)) sectionsDone++; // Iterate thought the lines until we reach the end of the section, then report as finished
        break;
      case fromWorker2 :> newImg[x2][y2]:
        if ((x2 + 1) < (IMWD)) x2++;
        else {
          x2 = IMWD/2;
          y2++;
        }
        if (y2 == (IMHT/4)) sectionsDone++;
        break;
      case fromWorker3 :> newImg[x3][y3]:
        if ((x3 + 1) < (IMWD/2)) x3++;
        else {
          x3 = 0;
          y3++;
        }
        if (y3 == (IMHT/2)) sectionsDone++;
        break;
      case fromWorker4 :> newImg[x4][y4]:
        if ((x4 + 1) < (IMWD)) x4++;
        else {
          x4 = IMWD/2;
          y4++;
        }
        if (y4 == (IMHT/2)) sectionsDone++;
        break;
    }
  }
}

// Operates on half the image, reading from and writing to the data streams directly
void distributor2(chanend data_in, chanend data_out, chanend fromDist1) {
  uchar img[ IMWD ][ IMHT/2 + 2 ], newImg[ IMWD ][ IMHT/2 + 2 ];
  int start, writing;
  printf( "Distributor 2 waiting to start.\n" );
  fromDist1 :> start;
  printf( "Reading bottom half of image\n" );
  for( int x = 0; x < IMWD; x++ ) data_in :> img[x][IMHT/2];   // Get the first line from the top half
  for( int x = 0; x < IMWD; x++ ) data_in :> img[x][IMHT/2 + 1];   // Get the last line from the top half
  for( int y = 0; y < IMHT/2; y++ ) {   //go through all lines
    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
      data_in :> img[x][y];              //read the pixel value
    }
  }
  for (int cycle = 0; cycle < maxCycles; cycle++) {
    /printf("\nDistributor 2 starting cycle %d...\n", cycle);/
    fromDist1 :> start; // Synch with distributor1
    if (cycle > 0) {
      // Report the borders for distributor1 - the top and bottom lines in the bottom half
      for (int x = 0; x < IMWD; x++) {
        fromDist1 <: newImg[x][0];
        fromDist1 <: newImg[x][IMHT/2 -1];
      }
      // Update the borders from distributor1 - the top and bottom lines in the top half
      for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
        fromDist1 :> img[x][IMHT/2];
        fromDist1 :> img[x][IMHT/2 + 1];
      }
      // Collect the rest of the image half
      for (int y = 0; y < IMHT/2; y++) {
        for (int x = 0; x < IMWD; x++) {
          img[x][y] = newImg[x][y];
        }
      }
    }
    /printf("Bottom half of image has %d live cells.\n", total(img));/
    // Check with distributor if writing out;
    fromDist1 :> writing;
    if (writing) {
      for( int y = 0; y < IMHT/2; y++ ) {   //go through all lines
        for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
          data_out <: (uchar) img[x][y]; //send some modified pixel out
        }
      }
    }
    fromDist1 :> start; // Synch with distributor1 (in case of tilt pause)
    // Edit the image according to the GoL rules
    // Farm out the work to subthreads
    chan workers[4]; // channels for the workers to communicate with gatherer
    par {
      gatherer(newImg, workers[0], workers[1], workers[2], workers[3]);
      worker(img, 0, 0, (IMWD/2), (IMHT/4), workers[0]);
      worker(img, (IMWD/2), 0, IMWD, (IMHT/4), workers[1]);
      worker(img, 0, (IMHT/4), (IMWD/2), (IMHT/2), workers[2]);
      worker(img, (IMWD/2), (IMHT/4), IMWD, (IMHT/2), workers[3]);
    }
    /printf("Bottom half of new image has %d live cells.\n", total(newImg));/
    /printf( "\nCycle %d completed on Distributor 2...\n", cycle);/
  }
  printf("Distributor 2 finished processing.\n");
}

// Operates on the other half of the image and instructs distributor2
void distributor(chanend data_in, chanend data_out, chanend fromAcc, chanend fromButtons, chanend toLEDs, chanend toDist2){
  uchar img[ IMWD ][ IMHT/2 + 2 ], newImg[ IMWD ][ IMHT/2 + 2 ];
  int tilted, button, leds = 8;
  long long endTime, startTime;
  long long timings[maxCycles];
  timer tmr;
  // Initialise both arrays
  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, (IMWD*8) );
  toLEDs <: leds;
  printf( "Waiting for start button...\n" );
  fromButtons :> button;
  leds = 4;
  toLEDs <: leds;
  toDist2 <: 1;
  data_in <: 1;
  printf( "Reading top half of image\n" );
  // Build the image half and the borders of the botton half
  for( int y = 0; y < IMHT/2 + 2; y++ ) {   //go through all lines
    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
      data_in :> img[x][y];              //read the pixel value
    }
  }
  printf( "Processing...\n" );
  // Iterate life cycles on the image
  for (int cycle = 0; cycle < maxCycles; cycle++) {
    /printf("\nDistributor 1 starting cycle %d...\n", cycle);/
    tmr :> startTime;
    toDist2 <: 1; // Synch with distributor2
    if (cycle > 0) {
      // Update the borders from distributor2 - the top and bottom lines in the bottom half
      for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
        toDist2 :> img[x][IMHT/2];
        toDist2 :> img[x][IMHT/2 + 1];
      }
      // Report the borders for distributor2 - the top and bottom lines in the top half
      for (int x = 0; x < IMWD; x++) {
        toDist2 <: newImg[x][0];
        toDist2 <: newImg[x][IMHT/2 - 1];
      }
      // Collect the rest of the image half
      for (int y = 0; y < IMHT/2; y++) {
        for (int x = 0; x < IMWD; x++) {
          img[x][y] = newImg[x][y];
        }
      }
    }
    /printf("Top half of image has %d live cells.\n", total(img));/
    // Check board orientation
    fromAcc <: 1;
    fromAcc :> tilted;
    // If tilted, wait for board to be flat and also check for output requests
    int outputted = 0;
    if (tilted) {
      leds = 8;
      toLEDs <: leds;
      printf("Board tilted, paused.\n");
    }
    while (tilted) {
      if (!outputted) {
        fromButtons <: 1;
        fromButtons :> button;
        if (button == 13) {
          printf("Writing out image.\n");
          toDist2 <: 1; // Tell distributor2 to write too
          leds += 2;
          toLEDs <: leds;
          // Output the resulting image
          data_out <: 1;
          for( int y = 0; y < IMHT/2; y++ ) {   //go through all lines
            for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
              data_out <: (uchar) img[x][y]; //send some modified pixel out
            }
          }
          leds -= 2;
          toLEDs <: leds;
          outputted = 1;
        }
      }
      fromAcc <: 1;
      fromAcc :> tilted;
      if (!tilted) printf("Board flat, resuming.\n");
    }
    leds = 4;
    toLEDs <: leds;

    // Check for output request if we didn't already do one this cycle
    if (!outputted) {
      fromButtons <: 1;
      fromButtons :> button;
      if (button == 13) {
        printf("Writing out image.\n");
        toDist2 <: 1; // Tell distributor2 to write too
        leds += 2;
        toLEDs <: leds;
        // Output the resulting image
        data_out <: 1;
        for( int y = 0; y < IMHT/2; y++ ) {   //go through all lines
          for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
            data_out <: (uchar) img[x][y]; //send some modified pixel out
          }
        }
        leds -= 2;
        toLEDs <: leds;
        outputted = 1;
      }
    }
    if (!outputted) toDist2 <: 0; // Tell distributor2 not to write this cycle
    toDist2 <: 1; //Synch with distributor2 after potential board tilt

    // Edit the image according to the GoL rules
    // Farm out the work to subthreads
    leds += 1;
    toLEDs <: leds;
    chan workers[4]; // channels for the workers to communicate with gatherer
    par {
      gatherer(newImg, workers[0], workers[1], workers[2], workers[3]);
      worker(img, 0, 0, (IMWD/2), (IMHT/4), workers[0]);
      worker(img, (IMWD/2), 0, IMWD, (IMHT/4), workers[1]);
      worker(img, 0, (IMHT/4), (IMWD/2), (IMHT/2), workers[2]);
      worker(img, (IMWD/2), (IMHT/4), IMWD, (IMHT/2), workers[3]);
    }
    leds -= 1;
    toLEDs <: leds;
    /printf("Top half of new image has %d live cells.\n", total(newImg));/
    /printf( "\nCycle %d completed on Distributor 1...\n", cycle);/
    tmr :> endTime;
    timings[cycle] = endTime - startTime;
  }
  printf("Distributor 1 finished processing.\n");
  printf("Processing took %f seconds. The longest cycle was cycle %d at %f seconds.\n", ((float)sum(timings, maxCycles)/100000000), largest(timings, maxCycles), ((float)max(timings, maxCycles)/100000000));
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//
/////////////////////////////////////////////////////////////////////////////////////////

void DataOutStream(char outfname[], chanend fromDist1, chanend fromDist2) {
  int res;
  uchar line[ (IMWD*8) ];
  while (1) {
    fromDist1 :> int start;
    //Open PGM file
    printf( "DataOutStream: Start...\n" );
    res = _openoutpgm( outfname, (IMWD*8), IMHT );
    if( res ) {
      printf( "DataOutStream: Error opening %s\n.", outfname );
      return;
    }

    //Compile each line of the image and write the image line-by-line
    for( int y = 0; y < IMHT; y++ ) {
      for( int x = 0; x < IMWD; x++ ) {
        uchar chunk;
        // Read the lines in order (outputting doesn't really need to be fast)
        if (y < IMHT/2) fromDist1 :> chunk;
        else fromDist2 :> chunk;
        for (int n = 0; n < 8; n++) {
          line[ x*8 + n ] = ((chunk >> 7-n) & 1) * 255;
        }
      }
      _writeoutline( line, (IMWD*8) );
      /printf( "DataOutStream: Line written...\n" );/
    }

    //Close the PGM image
    _closeoutpgm();
    printf( "DataOutStream: Done...\n" );
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {
    // Wait for distributor to ask for a tilt check
    toDist :> int temp;
    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor
    if (x>30) tilted = 1;
    else tilted = 0;
    toDist <: tilted;
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {
  i2c_master_if i2c[1];               //interface to orientation

  chan c_inIO, c_outIO, c_inIO2, c_outIO2, c_control, distToButtons, distToLEDs, dist1to2;    //extend your channel definitions here

  par {
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0]: orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[0]: buttonListener(buttons, distToButtons);
    on tile[0]: distributor(c_inIO, c_outIO, c_control, distToButtons, distToLEDs, dist1to2); //thread to coordinate work on image
    on tile[1]: showLEDs(leds, distToLEDs);
    on tile[1]: DataInStream("Builder.pgm", c_inIO, c_inIO2);          //thread to read in a PGM image
    on tile[1]: DataOutStream("Builderout.pgm", c_outIO, c_outIO2);       //thread to write out a PGM image
    on tile[1]: distributor2(c_inIO2, c_outIO2, dist1to2); //thread to coordinate work on image
  }

  return 0;
}
