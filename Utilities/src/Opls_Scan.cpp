/*!\file
  \brief Structures and functions used to read and write OPLS files.
  \author Alexander Luchs, Riley Spahn, Seth Wooten
 
 */

#include "Opls_Scan.h"
#include <exception>
#include <stdexcept>

Opls_Scan::Opls_Scan(string filename){
   fileName = filename;
}

Opls_Scan::~Opls_Scan(){
    oplsTable.clear();
}

int Opls_Scan::scanInOpls(string filename){
    int numOfLines=0;
    ifstream oplsScanner(filename.c_str());
    if( !oplsScanner.is_open() )
        return -1;
    else {
        string line; 
        while( oplsScanner.good() )
        {
            numOfLines++;
            getline(oplsScanner,line);

            //check if it is a commented line,
            //or if it is a title line
            try{
                if(line.at(0) != '#' && numOfLines > 1)
                    addLineToTable(line,numOfLines);
            }
            catch (std::out_of_range& e){}
        }
        oplsScanner.close();
    }

    return 0;
}

void Opls_Scan::addLineToTable(string line, int numOfLines){
    string hashNum;
    int secCol;
    double charge,sigma,epsilon;	 
    string name,extra;
    stringstream ss(line);

    //check to see what format it is opls, V value, or neither
    int format = checkFormat(line);
              
    if(format == 1){      	
        ss >> hashNum >> secCol >> name >> charge >> sigma >> epsilon;
            
        Atom temp = createAtom(0, -1, -1, -1, sigma, epsilon, charge);
        pair<map<string,Atom>::iterator,bool> ret;
        ret = oplsTable.insert( pair<string,Atom>(hashNum,temp) );

        if (ret.second==false)
            cerr << "Err Opls Scanner: element "<< hashNum << "already existed" <<endl;
    }
    else if(format == 2)
    {
        double v0,v1,v2,v3;
        ss >> hashNum >> v0 >> v1 >> v2 >> v3 ;
        Fourier vValues = {v0,v1,v2,v3};
        pair<map<string,Fourier>::iterator,bool> ret2;
        ret2 = vTable.insert( pair<string,Fourier>(hashNum,vValues) );

        if (ret2.second==false)
            cerr << "Err Opls Scanner: element "<< hashNum << "already existed" <<endl;
    }
    else
        cerr << "Err Opls Scanner: line "<< numOfLines <<"contains bad format\n---" << line<< endl;

}

int Opls_Scan::checkFormat(string line){   	 
    int hashNum, secCol;
    double charge,sigma,epsilon;
    string name,extra;
    stringstream iss(line);

    double v1,v2,v3,v4;
    stringstream issw(line);

    //see if format is the V values for the diherdral format
    if((issw >> hashNum >> v1 >> v2 >> v3 >> v4) )
        return 2;
    //else see if format is normal opls format
    else if((iss >> hashNum >> secCol >> name >> charge >> sigma >> epsilon ))
        return 1;
    //if neither return -1
    else
        return -1;
}

Atom Opls_Scan::getAtom(string hashNum){
    if(oplsTable.count(hashNum)>0 ){
	     return oplsTable[hashNum];
	 }
	 else{
	    cerr << "Index does not exist" <<endl;
		 return createAtom(0, -1, -1, -1, -1, -1, -1);
	 }
}

double Opls_Scan::getSigma(string hashNum){
    if(oplsTable.count(hashNum)>0 ){
        Atom temp = oplsTable[hashNum];
        return temp.sigma;
    }
    else{
        cerr << "Index does not exist" <<endl;
        return -1;
    }
}

double Opls_Scan::getEpsilon(string hashNum){
    if(oplsTable.count(hashNum)>0 ){
        Atom temp = oplsTable[hashNum];
        return temp.epsilon;
    }
    else{
        cerr << "Index does not exist" <<endl;
        return -1;
    }
}

double Opls_Scan::getCharge(string hashNum){
    if(oplsTable.count(hashNum)>0 ){
        Atom temp = oplsTable[hashNum];
        return temp.charge;
    }
    else{
        cerr << "Index does not exist" <<endl;
        return -1;
    }
}

Fourier Opls_Scan::getFourier(string hashNum){
    if(vTable.count(hashNum)>0 ){
        Fourier temp = vTable[hashNum];
        return temp;
    }
    else{	    
        cerr << "Index does not exist" <<endl;
        Fourier temp ={-1,-1,-1,-1};
        return temp;
    }
}
