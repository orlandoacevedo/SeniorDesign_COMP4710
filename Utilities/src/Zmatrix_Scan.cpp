#include "Zmatrix_Scan.h"

//constructor
Zmatrix_Scan::Zmatrix_Scan(string filename, Opls_Scan* oplsScannerRef){
   fileName = filename;
    oplsScanner = oplsScannerRef;
    startNewMolecule = false;
}

Zmatrix_Scan::~Zmatrix_Scan(){
}

//scans in the zmatrix file and adds entries to the table
int Zmatrix_Scan::scanInZmatrix(){
    int numOfLines=0;
   ifstream zmatrixScanner(fileName.c_str());
   if( !zmatrixScanner.is_open() )
      return -1;
   else {
      string line; 
      while( zmatrixScanner.good() )
      {
        numOfLines++;
        getline(zmatrixScanner,line);

        Molecule workingMolecule;

        //check if it is a commented line,
		  //or if it is a title line
        try{
            if(line.at(0) != '#' && numOfLines > 1)
                parseLine(line,numOfLines);
        }
        catch(std::out_of_range& e){}

        if (startNewMolecule){
            Atom* atomArray;
            Bond* bondArray;
            Angle* angleArray;
            Dihedral* dihedralArray;

            atomArray = (Atom*) malloc(sizeof(Atom) * atomVector.size());
            bondArray = (Bond*) malloc(sizeof(Bond) * bondVector.size());
            angleArray = (Angle*) malloc(sizeof(Angle) * angleVector.size());
            dihedralArray = (Dihedral*) malloc(sizeof(Dihedral) * dihedralVector.size());
            
            for (int i = 0; i < atomVector.size(); i++){
                atomArray[i] = atomVector[i];
            }
            for (int i = 0; i < bondVector.size(); i++){
                bondArray[i] = bondVector[i];
            }
            for (int i = 0; i < angleVector.size(); i++){
                angleArray[i] = angleVector[i];
            }
            for (int i = 0; i < dihedralVector.size(); i++){
                dihedralArray[i] = dihedralVector[i];
            }

            moleculePattern.push_back(createMolecule(-1, atomArray, angleArray, bondArray, dihedralArray, 
                                 atomVector.size(), angleVector.size(), bondVector.size(), dihedralVector.size()));

            atomVector.clear();
            bondVector.clear();
            angleVector.clear();
            dihedralVector.clear();

            startNewMolecule = false;
        } 
      }

      zmatrixScanner.close();
   }
}

// adds a string line into the table
void Zmatrix_Scan::parseLine(string line, int numOfLines){

    string atomID, atomType, oplsA, oplsB, bondWith, bondDistance, angleWith, angleMeasure, dihedralWith, dihedralMeasure;
	
    stringstream ss;
     
	 //check if line contains correct format
	 int format = checkFormat(line);
	 //cout <<"-- " <<line<<endl; //DEBUG
	 //cout <<"Format: "<< format << endl; //DEBUG
	 
	 if(format == 1){
	    //read in strings in columns and store the data in temporary variables
        ss << line;    	
        ss >> atomID >> atomType >> oplsA >> oplsB >> bondWith >> bondDistance >> angleWith >> angleMeasure >> dihedralWith >> dihedralMeasure;
	 
        //setup structures for permanent encapsulation
        Atom lineAtom;
        Bond lineBond;
        Angle lineAngle;
        Dihedral lineDihedral;

        if (oplsA.compare("-1") != 0)
        {
            lineAtom = oplsScanner->getAtom(oplsA);
            lineAtom.id = atoi(atomID.c_str());
            atomVector.push_back(lineAtom);
        }
        else//dummy atom
        {
            lineAtom = createAtom(atoi(atomID.c_str()), -1, -1, -1);
            atomVector.push_back(lineAtom); 
        }

        if (bondWith.compare("0") != 0){
            lineBond.atom1 = lineAtom.id;
            lineBond.atom2 = atoi(bondWith.c_str());
            lineBond.distance = atof(bondDistance.c_str());
				lineBond.variable = false;
            bondVector.push_back(lineBond);
        }

        if (angleWith.compare("0") != 0){
            lineAngle.atom1 = lineAtom.id;
            lineAngle.atom2 = atoi(angleWith.c_str());
            lineAngle.value = atof(angleMeasure.c_str());
				lineAngle.variable = false;
            angleVector.push_back(lineAngle);
        }

        if (dihedralWith.compare("0") != 0){
            lineDihedral.atom1 = lineAtom.id;
            lineDihedral.atom2 = atoi(dihedralWith.c_str());
            lineDihedral.value = atof(dihedralMeasure.c_str());
				lineDihedral.variable = false;
            dihedralVector.push_back(lineDihedral);
        }
    }
    else if(format == 2)
        startNewMolecule = true;
	 else if(format == 3){
	     startNewMolecule = true;
	 }
	 if (previousFormat >= 3 && format == -1)
	     handleZAdditions(line, previousFormat);
	 		  
	     
	 previousFormat = format;
}

// check if line contains the right format...
int Zmatrix_Scan::checkFormat(string line){
    int format =-1; 
    stringstream iss(line);
	 stringstream iss2(line);
	 string atomType, someLine;
	 int atomID, oplsA, oplsB, bondWith, angleWith,dihedralWith,extra;
	 double bondDistance, angleMeasure, dihedralMeasure;	 
	 
	 // check if it is the normal 11 line format
	  if( iss >> atomID >> atomType >> 
	      oplsA >> oplsB >> 
			bondWith >> bondDistance >> 
			angleWith >> angleMeasure >> 
			dihedralWith >> dihedralMeasure >> extra)
			format = 1;
	 else{
	     someLine = line;
	     if(someLine.find("TERZ")!=string::npos)
		      format = 2;
		  else if(someLine.find("Geometry Variations follow")!=string::npos)
		      format = 3;
		  else if(someLine.find("Variable Bonds follow")!=string::npos)
		      format = 4;
		  else if(someLine.find("Additional Bonds follow")!=string::npos)
		      format = 5;
		  else if(someLine.find("Harmonic Constraints follow")!=string::npos)
		      format = 6;
		  else if(someLine.find("Variable Bond Angles follow")!=string::npos)
		      format = 7;
		  else if(someLine.find("Additional Bond Angles follow")!=string::npos)
		      format = 8;
		  else if(someLine.find("Variable Dihedrals follow")!=string::npos)
		      format = 9;
		  else if(someLine.find("Additional Dihedrals follow")!=string::npos)
		      format = 10;
		 else if(someLine.find("Domain Definitions follow")!=string::npos)
		      format = 11;
	 	 else if(someLine.find("Final blank line")!=string::npos)
		      format = -2;  
	 }	 
	 return format;
}

void Zmatrix_Scan::handleZAdditions(string line, int cmdFormat){
    vector<int> atomIds;
	 int id;
	 stringstream tss(line.substr(0,15) );
	 if(line.find("AUTO")!=string::npos){
	 }
	 else{
        while(tss >> id){
            atomIds.push_back(id);
            if(tss.peek()=='-'||tss.peek()==','||tss.peek()==' ')
                tss.ignore();
        }
		  int start, end=0;
		  if( atomIds.size()== 1){
		     start = atomIds[0];
			  end = atomIds[0]; 
			  }
		  else if(atomIds.size() == 2){
		     start = atomIds[0]; end = atomIds[1];
			 }
		  //cout << "start: " << start<< " end: " <<end <<endl; //DEBUG
            switch(cmdFormat){
	             case 3:
    				// Geometry Variations follow 
		              break;
    		      case 4:
    				// Variable Bonds follow
					    for(int i=0; i< moleculePattern[0].numOfBonds; i++){
					        if(  moleculePattern[0].bonds[i].atom1 >= start &&  moleculePattern[0].bonds[i].atom1 <= end){
							       //cout << "Bond Atom1: "<<  moleculePattern[0].bonds[i].atom1 << " : " <<  moleculePattern[0].bonds[i].variable<<endl;//DEBUG
			                   moleculePattern[0].bonds[i].variable = true;
									 }
						 }
    		          break;
    		      case 5:
    				//  Additional Bonds follow 
    		          break;
    		      case 6:
    				// Harmonic Constraints follow 
    		          break;
    		      case 7:
    				//  Variable Bond Angles follow
					    for(int i=0; i<  moleculePattern[0].numOfAngles; i++){
					        if(  moleculePattern[0].angles[i].atom1 >= start && moleculePattern[0].angles[i].atom1 <= end){
							      //cout << "Angle Atom1: "<<  moleculePattern[0].angles[i].atom1 << " : " << moleculePattern[0].angles[i].variable << endl;//DEBUG
					            moleculePattern[0].angles[i].variable = true;
									}
						 }
    		          break;
    		      case 8:
    				// Additional Bond Angles follow
    		          break;
    		      case 9:
    				// Variable Dihedrals follow
					    for(int i=0; i< moleculePattern[0].numOfDihedrals; i++){
					        if(  moleculePattern[0].dihedrals[i].atom1 >= start &&  moleculePattern[0].dihedrals[i].atom1 <= end ) {
							      //cout << "Dihedral Atom1: "<<  moleculePattern[0].dihedrals[i].atom1 << " : " <<   moleculePattern[0].dihedrals[i].variable << endl;//DEBUG
					            moleculePattern[0].dihedrals[i].variable = true;
									}
						 }
    		          break;
    		      case 10:
    				//  Domain Definitions follow
    		          break;
					default:
					//Do nothing
					    break;
		  }
	 }
}

//return a vector of all the molecules scanned in.
//resed the id's of all molecules and atoms to be the location in Atom array
//based on the startingID. Atoms adn Molecules should be stored one behind the other.
vector<Molecule> Zmatrix_Scan::buildMolecule(int startingID){
    vector<Molecule> newMolecules = moleculePattern;
    
	 for (int i = 0; i < newMolecules.size(); i++)
    {
	     if(i == 0){
		      newMolecules[i].id = startingID;
		  }
		  else
		      newMolecules[i].id = newMolecules[i-1].id + newMolecules[i-1].numOfAtoms;  
		  		
	     /* //Why is this needed? these values are added and set in the createMolecule() function
	     //called earlier
        newMolecules[i].numOfAtoms = sizeof(*(newMolecules[i].atoms)) / sizeof(Atom);
        newMolecules[i].numOfBonds = sizeof(*(newMolecules[i].bonds)) / sizeof(Bond);
        newMolecules[i].numOfAngles = sizeof(*(newMolecules[i].angles)) / sizeof(Angle);
        newMolecules[i].numOfDihedrals = sizeof(*(newMolecules[i].dihedrals)) / sizeof(Dihedral);*/
    }

    for (int j = 0; j < newMolecules.size(); j++)
    {
        Molecule newMolecule = newMolecules[j];
        //map unique IDs to atoms within structs based on startingID
        for(int i = 0; i < newMolecule.numOfAtoms; i++){
            int atomID = newMolecule.atoms[i].id - 1;
            newMolecule.atoms[i].id = atomID + startingID;
        }
        for (int i = 0; i < newMolecule.numOfBonds; i++){
            int atom1ID = newMolecule.bonds[i].atom1 - 1;
            int atom2ID = newMolecule.bonds[i].atom2 - 1;
            
            newMolecule.bonds[i].atom1 = atom1ID + startingID;
            newMolecule.bonds[i].atom2 = atom2ID + startingID;
        }
        for (int i = 0; i < newMolecule.numOfAngles; i++){
            int atom1ID = newMolecule.angles[i].atom1 - 1;
            int atom2ID = newMolecule.angles[i].atom2 - 1;
            
            newMolecule.angles[i].atom1 = atom1ID + startingID;
            newMolecule.angles[i].atom2 = atom2ID + startingID;
        }
        for (int i = 0; i < newMolecule.numOfDihedrals; i++){
            int atom1ID = newMolecule.dihedrals[i].atom1 - 1;
            int atom2ID = newMolecule.dihedrals[i].atom2 - 1;
            
            newMolecule.dihedrals[i].atom1 = atom1ID + startingID;
            newMolecule.dihedrals[i].atom2 = atom2ID + startingID;
        }
    }

    return newMolecules;
}