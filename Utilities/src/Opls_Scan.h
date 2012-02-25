#ifndef OPLS_SCAN_H
#define OPLS_SCAN_H

// writing on a text file
#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <map>
#include <exception>
#include <stdexcept>
#include "metroUtil.h"
using namespace std;

//Struct that holds the Fourier Coefficents 
struct Fourier
{
    double vValues[4];
};

class Opls_Scan{
   private:
      map<string,Atom> oplsTable; //"HashTable" the holds all opls ref.
		map<string,Fourier> vTable;
      string fileName;
		
		/**
		Parses out a line from the opls file and gets (sigma, epsiolon, charge)
		adds an entry to the map at the hash number position, 
		calls sub-function checkFormat()
		@param line - a line from the opls file
		@param numOflines - number of lines previously read in, used for error output
		*/
      void addLineToTable(string line, int numOfLines);
		
		/**
		Checks the format of the line being read in
		returns false if the format of the line is invalid
		@param line -  a line from the opls file
		*/
		int checkFormat(string line);

   public:
      Opls_Scan(string filename); // constructor
      ~Opls_Scan();
		
		/**
		Scans in the opls File calls sub-function addLineToTable
		@param filename - the name/path of the opls file
		*/
      int scanInOpls(string filename); 
						
		/**
		Returns an Atom struct based on the hashNum (1st col) in Z matrix file
		The Atom struct has -1 for x,y,z and has the hashNum for an id. 
		sigma, epsilon, charges
		@param hashNum -  the hash number (1st col) in Z matrix file
		*/
		Atom getAtom(string hashNum);
		
		/**
		Returns the sigma value based on the hashNum (1st col) in Z matrix filee
		@param hashNum -  the hash number (1st col) in Z matrix file
		*/
		double getSigma(string hashNum);
		
		/**
		Returns the epsilon value based on the hashNum (1st col) in Z matrix filee
		@param hashNum -  the hash number (1st col) in Z matrix file
		*/
		double getEpsilon(string hashNum);
		
		/**
		Returns the charge value based on the hashNum (1st col) in Z matrix filee
		@param hashNum -  the hash number (1st col) in Z matrix file
		*/
		double getCharge(string hashNum);
		
		/**
		Returns the Fourier Coefficents (v values) based on the hashNum (1st col) in Z matrix file
		@param hashNum -  the hash number (1st col) in Z matrix file
		*/
		Fourier getFourier(string hashNum);

};

#endif // OPLS_SCAN_H
