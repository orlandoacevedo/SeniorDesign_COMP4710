#include "metroUtil.h"


//create an instance of an Atom struct
Atom createAtom(unsigned long id, double x, double y, double z, double sigma, double epsilon, double charge){
    Atom atom;
    atom.id = id;
    atom.x = x;
    atom.y = y;
    atom.z = z;
    atom.sigma = sigma;
    atom.epsilon = epsilon;
    atom.charge = charge;

    return atom;
}
//create an instance of an Atom struct
Atom createAtom(unsigned long id, double x, double y, double z, double sigma, double epsilon){
    Atom atom;
    atom.id = id;
    atom.x = x;
    atom.y = y;
    atom.z = z;
    atom.sigma = sigma;
    atom.epsilon = epsilon;

    return atom;
}
//create an instance of an Atom struct w/o sigma/epsilon constants
Atom createAtom(unsigned long id, double x, double y, double z){
    Atom atom;
    atom.id = id;
    atom.x = x;
    atom.y = y;
    atom.z = z;
    atom.sigma = 0.0;
    atom.epsilon = 0.0;

    return atom;
}


//create an instance of the Environment struct
Environment createEnvironment(double x, double y, double z, double maxTrans, double temp, int numOfAtoms){
    Environment enviro;
    enviro.x = x;
    enviro.y = y;
    enviro.z = z;
    enviro.maxTranslation = maxTrans;
    enviro.temperature = temp;
    enviro.numOfAtoms = numOfAtoms;

    return enviro;
}

//returns a instance of a bond structure
Bond createBond(int atom1, int atom2, int bondCount){
    Bond bond;
    bond.atom1 = atom1;
    bond.atom2 = atom2;
    return bond;
}

//returns an instance of a molecule object
Molecule createMolecule(int id, 
                        Atom *atoms, Bond *bonds, Dihedral *dihedrals, 
                        int atomCount, int bondCount, int dihedralCount){
    Molecule molecule;
    molecule.id = id;

    molecule.atoms = atoms;
    molecule.bonds = bonds;
    molecule.dihedrals = dihedrals;

    molecule.atomCount = atomCount;
    molecule.bondCount = bondCount;
    molecule.dihedralCount = dihedralCount;

    return molecule;
}

// returns an instance of the molecule struct
Molecule createMolecule(int id, Atom *atoms, int atomCount){
    Molecule molecule;
    molecule.id = id;
    molecule.atoms = atoms;
    molecule.atomCount = atomCount;

    return molecule;
}

//returns an instance of a bond
Bond createBond(int atom1, int atom2, double distance, bool variable){
    Bond bond;
    bond.atom1 = atom1;
    bond.atom2 = atom2;
    bond.distance = distance;
    bond.variable = variable;

    return bond;
}

//returns an instance of a dihedral
Dihedral createDihedral(int atom1, int atom2, double distance, bool variable){
    Dihedral dihedral;

    dihedral.atom1 = atom1;
    dihedral.atom2 = atom2;
    dihedral.distance = distance;
    dihedral.variable = variable;

    return dihedral;
}

Angle createAngle(int atom1, int atom2, double value, bool variable){
    Angle angle;
    angle.atom1 = atom1;
    angle.atom2 = atom2;
    angle.value = value;
    angle.variable = variable;

    return angle;
}

//utility to print off Atom coordinate data
void printAtoms(Atom *atoms, int count){
    for(int i = 0; i < count; i++){
        printf("%f, %f, %f\n", atoms[i].x, atoms[i].y, atoms[i].z);
    }
}

// writes atom information to a file.  Based on the siremol files.
void writeOutAtoms(Atom *atoms, Environment *enviro, string filename){
    FILE *atomOutput = fopen(filename.c_str(), "w");
/*
    for(int i = 0; i < enviro->numOfAtoms; i++){
       fprintf(atomOutput, "ATOM  %5d  %s   %s    1    %8.3f%8.3f%8.3f  1.00  0.00          %s\n",
               i+1, atoms[i].name.c_str(), atoms[i].name.c_str(), atoms[i].x, atoms[i].y, atoms[i].z, atoms[i].name.c_str());
    }*/
    fclose(atomOutput);
}
