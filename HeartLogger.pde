// Heart Logger V0.1
// Copyright 2011 Sensebridge.net
// Released under cc-sa-nc

import processing.serial.*;
import interfascia.*;
import java.io.File;

String SoftwareVersion = "0.1";  // outputted to data files for reference

Serial myPort; 
PrintWriter output;

final char SEPARATOR = ',';
final char LINEFEED = '\r';
final char CRRETURN = '\n';

int i = 1;
int graphPos = 1;
int inByte = -1;             
int xpos, ypos, zpos = 0;
int dataCount = 0;
boolean MoreData = true;
boolean startup = false;
boolean DataAcq = false;
boolean quit = false;
boolean SerialPortOpen = false;
boolean FirstPage = true;
int bufferedValue;
int xValue = 0;
int CurrentPage = 1;  // start at 1, because page 0 is actually the header, which
    // we never retrieve (and is in fact impossible to retrieve)
int NumPages = 0;
long logEPOCH = 0;
long firstLogEPOCH = 0;
String date;
String filename;
String HSVersion = "";

GUIController c;
IFButton b1, b2, b3, b4;
IFTextField t;
IFLabel l;

int buffer[] = new int[128];

void setup () {
  size(900, 550);      
  background(255);

  Date d = new Date();
  long current=d.getTime()/1000;
  date = new java.text.SimpleDateFormat("yyyyMMMdd").format(new java.util.Date (current*1000L));
  filename = "HeartData_" + date + ".csv";

  frameRate(30);

  c = new GUIController (this);
  
  b1 = new IFButton ("Grab & Log Data", 200, 120, 120, 17);
  b1.addActionListener(this);
  c.add (b1);

  b2 = new IFButton ("Open Serial Port", 40, 120, 120, 17);
  b2.addActionListener(this);
  c.add (b2);

  b3 = new IFButton ("Quit", 360, 120, 40, 17);
  b3.addActionListener(this);
  c.add (b3);
  
  b4 = new IFButton ("Grab ALL Data", 200, 170, 120, 17);
  b4.addActionListener(this);
  c.add (b4);
  
  t = new IFTextField("Text Field", 25, 30, 400);
  c.add(t);
  t.addActionListener(this);
  t.setValue(filename);
  
  l = new IFLabel("", 25, 70, 600);
  c.add(l);
  l.setLabel("Heart Logger V" + SoftwareVersion);
  //l.setLabel(t.getValue());
  
  println("Setup Done!");
}


/* ********** MAIN DRAW FUNCTION: looped ********** */
void draw () {
  if (startup) DoStartup();

  if (DataAcq)
  {
    GetDataLine_LogIt();
    
    // draw the data we just got and logged:
    for (i = 8; i<128; i++)
    {
      drawGraph(buffer[i]);
    }

    // once we've grabbed all the pages, stop grabbing data
    if (CurrentPage++ >= NumPages) StopDataAcq();
  }
  else
  {
    background(255);     
  }
  
  if (quit)
  {
     l.setLabel("Goodbye!");
     if (SerialPortOpen) myPort.stop();
     exit();
  }
}


void actionPerformed (GUIEvent e) {
  if (e.getSource() == b1) {
    StartDataAcq();
  }
  if (e.getSource() == b2) {
    startup = true;
  }
  if (e.getSource() == b3) {
    quit = true;
  }
  if (e.getSource() == b4) {
    GrabAllData();
  }
}

void StartDataAcq()
{
  // check if HS has been detected
  if (HSVersion == "")
  {
    l.setLabel("Heart Spark not present?  Have you Opened Serial Port?");
    return;  // bail now
  } 

  // check if the file they have specified already exists
  //filename = t.getValue();  // file.exists() doesn't seem to work this way!!
  filename = dataPath(t.getValue());
  File file = new File(filename);
  println("file: " + filename);
  if(file.exists())
  {
    l.setLabel("File already exists!  Rename and try again.");
    return;
  }

  // see if there is any data to get  
  GetNumPages();
  if (NumPages > 0)
  {
    DataAcq = true;
    l.setLabel((NumPages) + " pages of data to get");
  }
  else
  {
    l.setLabel("No data to get");
    return;
  }

    // start the file with a nice message
    output = createWriter(filename);
    output.println("Heart Spark by http://sensebridge.net/");
    output.println("Heart Spark V" + HSVersion + ";  Heart Logger V" + SoftwareVersion);

  // ok, now we do a bunch of prep work:
  //  - read the date from the Heart Spark, and log that to file
  //  - reset date on HS to computer date, i.e. resync
  //  - read number of pages of data that Heart Spark thinks it has
  //  - set flag that will start data acquisition from main loop

    // get date from the heart spark
    myPort.write(100); // 'd', get date
    delay(100);
    println(myPort.available());
    GetParseData(7);  // get the data into buffer[]
    parseDateIntoEPOCH();  // fill logEPOCH with our date
    output.print("RTC Date,");
    output.print(logEPOCH/1000L);
    output.print(",");
    outputDate();

    // now stuff out OUR date
    Date d = new Date();
    logEPOCH=d.getTime();
    output.print("Real Date,");
    output.print(logEPOCH/1000L);
    output.print(",");
    outputDate();
    
    // now set the date - later we make GUI for this
    myPort.write(68);  // 'D', set date
    while(myPort.available() == 0){delay(1);}
    bufferedValue = myPort.read();
    if (bufferedValue == 68)  // HeartSpark echos back the D to let us know it's ready
    {  // then the firmware is ready for the date, dump it in csv format
      date = new java.text.SimpleDateFormat("yy,MM,dd,HH,mm,ss,,").format(new java.util.Date (logEPOCH));
      myPort.write(date);
      myPort.write("\r\n");
    }
    println("finished setting date");
    
    // finish the header with a legend row
    output.println("TimeStamp,Minutes,Data,Date,Time,Year,Month,dayOfMonth,Hour,Minute,Second");  
    FirstPage = true;
    
  // throw away any junk that might be in the serial buffer: 
  delay(1000);
  while (myPort.available() > 0)
  print((char)myPort.read());
}


void GrabAllData()
{
  // check if HS has been detected
  if (HSVersion == "")
  {
    l.setLabel("Heart Spark not present?  Have you Opened Serial Port?");
    return;  // bail now
  } 

  // check if the file they have specified already exists
  //filename = t.getValue();  // file.exists() doesn't seem to work this way!!
  filename = dataPath(t.getValue());
  File file = new File(filename);
  println("file: " + filename);
  if(file.exists())
  {
    l.setLabel("File already exists!  Rename and try again.");
    return;
  }

  // set to get ALL data
  NumPages = 511;
  DataAcq = true;
  l.setLabel((NumPages) + " pages of data to get");

    // start the file with a nice message
    output = createWriter(filename);
    output.println("Heart Spark by http://sensebridge.net/");
    output.println("Heart Spark V" + HSVersion + ";  Heart Logger V" + SoftwareVersion);

  // ok, now we do a bunch of prep work:
  //  - read the date from the Heart Spark, and log that to file
  //  - reset date on HS to computer date, i.e. resync
  //  - read number of pages of data that Heart Spark thinks it has
  //  - set flag that will start data acquisition from main loop

    // get date from the heart spark
    myPort.write(100); // 'd', get date
    delay(100);
    println(myPort.available());
    GetParseData(7);  // get the data into buffer[]
    parseDateIntoEPOCH();  // fill logEPOCH with our date
    output.print("RTC Date,");
    output.print(logEPOCH/1000L);
    output.print(",");
    outputDate();

    // now stuff out OUR date
    Date d = new Date();
    logEPOCH=d.getTime();
    output.print("Real Date,");
    output.print(logEPOCH/1000L);
    output.print(",");
    outputDate();
    
    // now set the date - later we make GUI for this
    myPort.write(68);  // 'D', set date
    while(myPort.available() == 0){delay(1);}
    bufferedValue = myPort.read();
    if (bufferedValue == 68)  // HeartSpark echos back the D to let us know it's ready
    {  // then the firmware is ready for the date, dump it in csv format
      date = new java.text.SimpleDateFormat("yy,MM,dd,HH,mm,ss,,").format(new java.util.Date (logEPOCH));
      myPort.write(date);
      myPort.write("\r\n");
    }
    println("finished setting date");
    
    // finish the header with a legend row
    output.println("TimeStamp,Minutes,Data,Date,Time,Year,Month,dayOfMonth,Hour,Minute,Second");  
    FirstPage = true;
    
  // throw away any junk that might be in the serial buffer: 
  delay(1000);
  while (myPort.available() > 0)
  print((char)myPort.read());
}


void StopDataAcq()
{  // stop data acquisition, close the file, reset the Heart Spark logging
  output.flush(); // Write the remaining data
  output.close(); // Finish the file
  DataAcq = false;
  l.setLabel("Logged " + (CurrentPage-1) + " pages of data to " + filename);
  
  CurrentPage = 1;
  // and, most importantly, tell the HS to reset it's page counter
  // so that new data can be collected
  myPort.write(80);  // 'P', reset the eecounter to 1, which primes the
    // heart spark to start overwriting all the data we just grabbed
}

void GetNumPages()
{
  // ask HS for the number of pages of data it has

  // throw away any junk that might be in the serial buffer: 
  delay(1000);
  while (myPort.available() > 0)
    print((char)myPort.read());
  
  myPort.write(112);  // 112 is ascii for 'p', get current eecounter value
  GetParseData(1);
  NumPages = buffer[0] -1 ; // -1 because it actually hasn't written the 
    // page on which the counter is CURRENTLY at
}

void GetDataLine_LogIt()
{
  // ask for the next page (128 bytes) of data
  myPort.write(42);
  
  GetParseData(128);  // get all 128 bytes, parse them into buffer[]

  parseDateIntoEPOCH();
    
  if(FirstPage)
  {
    firstLogEPOCH = logEPOCH;  // grab data start time
    FirstPage = false;
  }

  // output the data to the file
  // the first row of each page, we add extra info, so it's done manually here

  // column 1: UNIX EPOCH  
  output.print(logEPOCH/1000L);
  output.print("." + (logEPOCH - (logEPOCH/1000L)*1000L));
  output.print(",");
  
  // column 2: minutes since start of logging, super useful in scatter plot
  float minutes = (float)(logEPOCH - firstLogEPOCH) / 60000.0;
  output.print(minutes);
  output.print(",");
  
  // column 3: heart date data (the first one in this page)
  //logData(buffer[7]);
  output.print(buffer[7]);
  output.print(",");
  
  // columns 4 & 5: pretty print date & time  
  outputDate();  

  // ok, now we're ready to just dump the other 120 data points
  for (i = 8; i<128; i++)
  {
    logData(buffer[i]);
  }

}

void parseDateIntoEPOCH()
{
  // now for date
  String initialDateStamp = "2009 06 12 03 34 56";
  //initialDateStamp = print("%i %i %i %i %i %i %i", buffer[1]+2000, buffer[2], buffer[3],buffer[4], buffer[5], buffer[6]);
  initialDateStamp = "" + (buffer[1]+2000) + " "  + buffer[2] + " " + buffer[3] + " "  + buffer[4] + " " + buffer[5] + " " + buffer[6];
  //initialDateStamp = "" + (buffer[6]+2000) + " "  + buffer[5] + " " + buffer[4] + " "  + buffer[3] + " " + buffer[2] + " " + buffer[1];
  DateFormat stampFormat = new SimpleDateFormat("yyyy MM dd HH mm ss");
  Date initialDate = null;
  try 
  {
    initialDate = stampFormat.parse(initialDateStamp);
    logEPOCH = initialDate.getTime();
  }
  catch (Exception e) 
  {
    println("Unable to parse date stamp");    
    logEPOCH = 946702800*1000;  // jan 1st 2000 0:0:0
  }  
}


void outputDate()
{  // NOTE: uses only logEPOCH to know what the date is,
   // you should call parseDateIntoEPOCH before calling this!
  Date d = new Date();
  String date = new java.text.SimpleDateFormat("dd MMM yyyy").format(new java.util.Date (logEPOCH));
  output.print(date);
  output.print(",");
  date = new java.text.SimpleDateFormat("HH:mm:ss").format(new java.util.Date (logEPOCH));
  output.print(date);
  output.print(",");
  date = new java.text.SimpleDateFormat("yy,MM,dd,HH,mm,ss,").format(new java.util.Date (logEPOCH));
  output.print(date);
  output.println(",");
}

void GetParseData(int howMany)
{
  // now grab it
  ZeroBuffer();
  MoreData = true;
  i = 0;
  while(MoreData)
  {    
     while(myPort.available() == 0){delay(1);}
     bufferedValue = myPort.read();
     
     if (bufferedValue == LINEFEED)
     {
       MoreData = false;
       break;
     }

     xValue = 0;
     while( (bufferedValue != SEPARATOR) && (bufferedValue != LINEFEED)) {
       // converts the Serial input, which is a stream of ascii characters, to integers
       // Shift the the current digits left one place
       xValue*= 10;
       // add the next value in the stream
       xValue += (bufferedValue - 48);
       while(myPort.available() == 0){delay(1);}      
       bufferedValue = myPort.read();
     }
     buffer[i++] = xValue;
     print(xValue);
     print(",");
     
     if (i == howMany) MoreData = false;
  }
  println("");

  // kill the final "\r" character and any other junk
  delay(100);
  while (myPort.available() > 0){myPort.read();}
}

void ZeroBuffer()
{
  for (i = 0; i<128; i++)
    buffer[i] = 0;
}

void drawGraph (int data) {

  stroke(255,0,0,150);
  line(graphPos, height, graphPos, height - data*2);  
  
  if (graphPos >= width-2) {
    graphPos = 0;
    background(255); 
  } 
  else {
    graphPos++;
  }
}

void logData(int data)
{
  // log a single data point to file
  // three columns: epoch, minutes, heart rate
  if (data != 0){
  if (buffer[0] == 101)
    logEPOCH = logEPOCH + 60000/data;
  else if (buffer[0] == 102)
    logEPOCH = logEPOCH + 60000;
  }

  float minutes = (float)(logEPOCH - firstLogEPOCH) / 60000.0;
  output.print(logEPOCH/1000L);
  output.print("." + (logEPOCH - (logEPOCH/1000L)*1000L));
  output.print(",");
  output.print(minutes);
  output.print(",");  
  output.print(data);
  output.println(',');
}

void DoStartup()
{
    startup = false;  // try this only once
    char data[] = {'T', 'M', 'P'};  // just some random values...

    println("Opening serial port");

    println(Serial.list());
    try {myPort = new Serial(this, Serial.list()[0], 57600);}
    catch (Exception e){l.setLabel("Serial Port unavailable!"); background(255); return;}

    // OK, we do three things here:
    // toggle logging: make sure it's not logging while we are getting data, etc.
    // toggle chatter: turn off all the stuff that it sends normally, so
    //   that the only stuff on the channel is the stuff we ask for
    // get version number: this is where we prove that it is a HS
    //   and later of course we can act differently depending on the verison
    //   string that we get back.  

    SerialPortOpen = true;
    println("Serial Port Opened... checking for Heart Spark");
    delay(2000); // the arduino needs time to get itself ready for serial input...
   
    // we don't need to stop logging, and it's possible to leave the 
    // device in a no-logging state by accident, so I'm not doing
    // this call anymore... 
    //myPort.write(108);  // 'l', Toggle Logging, make sure it's not overwriting old data with new data!
    //delay(100);  // wait for another wake cycle
    
    myPort.write(99); // 'c', Toggle Chatter, make the Serial quiet except for data
    delay(500);  // wait to be sure all the junk has arrived
    while (myPort.available() > 0)
      print((char)myPort.read());  // throw away all the junk that's there now
        
    // OK, check if we actually have a Heart Spark open
    myPort.write(118); // 'v', get version number
    delay(500);
    //println(myPort.available());
    if (myPort.available() == 5) // 3 characters plus \r\n
    {
      data[0] = (char)myPort.read();
      data[1] = (char)myPort.read();
      data[2] = (char)myPort.read();
      HSVersion = new String(data);
      l.setLabel("Heart Spark V" + HSVersion + " detected");
    }
    else
    {
      //bail now, something is fishy
      myPort.stop();
      l.setLabel("No Heart Spark detected, is FTDI cable plugged in?");
      background(255); 
      return;
    }
    
    // throw away any junk that might be in the serial buffer: 
    delay(1000);
    while (myPort.available() > 0)
      print((char)myPort.read());

    background(255); 
}

