#ifndef METROCUDAUTIL_CUH
#define METROCUDAUTIL_CUH

#define DEBUG

#include <cstdlib>
#include <cuda.h>
#include <curand_kernel.h>
#include <math.h>
#include "../../Utilities/src/metroUtil.h"
#include <curand.h>
#define THREADS_PER_BLOCK 128
#define PI 3.14159265358979323


/**
  @param idx - the index in the 1 dimensional array of energies
  @return - the id of the X atom
*/
__device__ int getXFromIndex(int idx);

/**
  @param x - the id of the x atom
  @param idx - the index in the 1 dimensional array of energies
*/
__device__ int getYFromIndex(int x, int idx);

/**
  @param x - the variable to make periodic
  @param box - the size of the period
  @return - x after being made periodic
*/
__device__ double makePeriodic(double x, const double box);

/**
  @param x - the value to continue on the other side of the box
  @param box - the length of one side of the box (cube)
*/
double wrapBox(double x, double box);

/**
  Calculates the energy between 2 atoms
  @param atom1 - the first atom in the pair
  @param atom2 - the second atom in the pair
  @param enviro - the environmental variables
*/
__device__ double calc_lj(Atom atom1, Atom atom2, Environment enviro); 

/**
    Global function for GPU to assign random doubles to atom positions.
    @param dev_doubles - array of randomly generated doubles 0.0 to 1.0
    @param atoms - array of atoms to be positioned
    @param enviro - Environment of the simulation
*/
__global__ void assignAtomPositions(double *dev_doublesX, double *dev_doublesY, double *dev_doublesZ, Atom *atoms, Environment *enviro);

/**
  Generate random positions for atoms in the box
  nVidia CURAND reference: http://developer.download.nvidia.com/compute/cuda/5_0/toolkit/docs/CURAND_Library.pdf
  @param atoms - array of atoms to generate positions
  @param enviro - enviroment structure defining the box
*/
void generatePoints(Atom *atoms, Environment *enviro);

/**
  This is a wrapper function for the calcEnergy kernel.
  @param *atoms - the array of atoms
  @param enviro - the environmental variables
  @return - the total energy of the system.
*/
double calcEnergyWrapper(Atom *atoms, Environment *enviro);

/**
  Wrapper function for the calcEnergy kernel.
  @param molecules - array of molecules in the system
  @param enviro - the environment of the system.
*/
double calcEnergyWrapper(Molecule *molecules, Environment *enviro);

/**
  Calculates the energy between n atoms where n is the
  the number of threads in the block. The block's sum is then stored 
  in the energySum array at its block index position.
  @param *atoms - the array of atoms
  @param enviro - the environmental variables
  @param *energySum - the array of block sums
*/
__global__ void calcEnergy(Atom *atoms, Environment *enviro, double *energySum);

/**
  Calculates the charge portion of the force field energy calculation between two atoms.
  @param atom1 - the first atom in the calculation
  @param atom2 - the second atom in the calculation
  @return - the charge portion of the force field.
  
  Assigned to Alex
*/
__device__ double calcCharge(Atom atom1, Atom atom2, Environment *enviro);

/**
  Returns the "fudge factor" to be used in force field calculation.
  @param atom1 - the first atom in calculation
  @param atom2 - the second atom in the calculation
  @return - 1.0 if the atoms are in seperate molecules
            .5 if the bond traversal distance is greater or equal to 4
            0.0 if the bond traversal is less than 4

  Assigned to TBD
*/
__device__ double getFValue(Atom atom1, Atom atom2, Molecule *molecules, Environment *enviro);

/**
  Returns the bond distance between atom1 and atom2 in the molecule
  @param atom1 - the source atom in the molecule
  @param atom2 - the destination atom in the molecule
  @param molecule - the molecule that contains atom1 and atom 2
*/
__device__ int getDistance(Atom atom1, Atom atom2, Molecule molecule, Environment enviro);

/**
  Returns sqrt(d1 * d2)
  @param d1 - the first double in the calculation
  @param d2 - the second double in the calculation
  @return - sqrt(d1 * d2)
*/
__device__ double calcBlending(double d1, double d2);

/**
  Returns the molecule id from the atomid
  @param atom - the atom from which to find the molecule
  @param molecules - the list of molecules to be searched
  @param return - returns the id of the molecule
*/
__device__ int getMoleculeFromAtomID(Atom a1, Molecule *molecules, Environment enviro);

/**
  Rotates a molecule about a given atom a random amount
  @param molecule - the molecule to be rotated
  @param pivotAtom - the atom that the molecule is rotated about
  @param maxRotation - the maximum number of degrees for each axis of rotation

*/
void rotateMolecule(Molecule molecule, Atom pivotAtom, double maxRotation);

/****************************
  Begin Stubs for outputs
****************************/

/**
  This is currently a stub pending information from Dr. Acevedo
*/
double solventAccessibleSurfaceArea();

/**
  This is currently a stub pending information from Dr. Acevedo
*/
double soluteSolventDistributionFunction();

/**
  This is currently a stub pending information from Dr. Acevedo
*/
double atomAtomDistributionFunction();

/**
  This is currently a stub pending information from Dr. Acevedo
*/
double solventSolventTotalEnergy();

/**
  This is currently a stub pending information from Dr. Acevedo
*/
double soluteSolventTotalEnergy();


#ifdef DEBUG

/**
   @param atoms - array of atoms to be used in the atom1 parameter
   @param molecules - array of molecules to be used in the molecule parameter
   @param enviros - the array of environments to be used in the enviro parameter
   @param numberOfTests - the number of tests to be run. All other arrays must 
   be of length numberOfTests
 */
__global__ void testGetMoleculeFromID(Atom *atoms, Molecule *molecules,
        Environment enviros, int numberOfTests, int *answers);

/**
  Kernel function that will be used to test test calcBlending() function.
*/
__global__ void testCalcBlending(double *d1, double *d2, double *answers, int numberOfTests);

/**
  Kernel function that will be used to test the getFValue() function.
*/
__global__ void testGetFValue(Atom *atom1List, Atom *atom2List, Molecule *molecules, Environment *enviro, double *fValues, int numberOfTests);

/**
  Kernel function that will be used to test the calcCharge() function.
*/
__global__ void testCalcCharge();

/**
    Kernel call that will be used to test the getXFromIndexFunction
    @apram xValues - a series of xValues used to test
*/
__global__ void testGetXKernel(int *xValues, int totalTests);

/**
  Kernel function that will be used to test getYFromIndex device function
*/
__global__ void testGetYKernel(int *xValues, int *yValues, int numberOfTests);

/**
  Kernel function used to facilitate tests of the makePeriodic device function
*/
__global__ void testMakePeriodicKernel(double *x, double *box, int numberOfTests);

/**
  Kernel function used to facilitate tess of the wrap box device function
*/
__global__ void testWrapBoxKernel(double *x, double *box, int numberOfTests);

/**
  Kernel to test the calc_lj device function
*/
__global__ void testCalcLJ(Atom *atoms, Environment *enviro, double *energy);

/**
  Kernel function to test the calculation of bond distance between two atoms
*/
__global__ void testCalcGetDistance(Atom *atom1List, Atom *atom2List, Molecule molecule, Environment *enviro, int *distances, int numberOfTests);

#endif //DEBUG

#endif //METROCUDAUTIL_CUH
