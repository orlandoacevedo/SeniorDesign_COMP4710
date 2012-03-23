#include "metroCudaUtil.cuh"

//const int THREADS_PER_BLOCK = 128;

//calculates X (larger indexed atom) for energy calculation based on index in atom array
__device__ int getXFromIndex(int idx){
    int c = -2 * idx;
    int discriminant = 1 - 4 * c;
    int qv = (-1 + sqrtf(discriminant)) / 2;
    return qv + 1;
}

//calculates Y (smaller indexed atom) for energy calculation based on index in atom array
__device__ int getYFromIndex(int x, int idx){
    return idx - (x * x - x) / 2;
}

//apply periodic boundaries
__device__ double makePeriodic(double x, double box){
    
    while(x < -0.5 * box){
        x += box;
    }

    while(x > 0.5 * box){
        x -= box;
    }

    return x;

}

//keep coordinates with box
double wrapBox(double x, double box){

    while(x > box){
        x -= box;
    }
    while(x < 0){
        x += box;
    }

    return x;
}

void keepMoleculeInBox(Molecule *molecule, Environment *enviro){

    double maxX = 0.0;
    double maxY = 0.0;
    double maxZ = 0.0;

    //determine extreme boundaries for molecule
    for (int i = 0; i < molecule->numOfAtoms; i++){
        double currentX = molecule->atoms[i].x;
        double currentY = molecule->atoms[i].y;
        double currentZ = molecule->atoms[i].z;
        if (currentX > maxX)
           maxX = currentX;
        if (currentY > maxY)
            maxY = currentY;
        if (currentZ > maxZ)
            maxZ = currentZ;
    }

    //for each axis, determine if the molecule escapes the environment 
    //and translate it into the environment if it does
    if (maxX > enviro->x){
        for (int i = 0; i < molecule->numOfAtoms; i++){
            molecule->atoms[i].x -= (maxX - enviro->x);
        }
    }
    if (maxY > enviro->y){
        for (int i = 0; i < molecule->numOfAtoms; i++){
            molecule->atoms[i].y -= (maxY - enviro->y);
        }
    }
    if (maxZ > enviro->z){
        for (int i = 0; i < molecule->numOfAtoms; i++){
            molecule->atoms[i].z -= (maxZ - enviro->z);
        }
    }
}
//calculate Lennard-Jones energy between two atoms
__device__ double calc_lj(Atom atom1, Atom atom2, Environment enviro){
    //store LJ constants locally
    double sigma = atom1.sigma;
    double epsilon = atom1.epsilon;
    
    //calculate difference in coordinates
    double deltaX = atom1.x - atom2.x;
    double deltaY = atom1.y - atom2.y;
    double deltaZ = atom1.z - atom2.z;

    //calculate distance between atoms
    deltaX = makePeriodic(deltaX, enviro.x);
    deltaY = makePeriodic(deltaY, enviro.y);
    deltaZ = makePeriodic(deltaZ, enviro.z);

    const double r2 = (deltaX * deltaX) +
                      (deltaY * deltaY) + 
                      (deltaZ * deltaZ);

    //calculate terms
    const double sig2OverR2 = pow(sigma, 2) / r2;
    const double sig6OverR6 = pow(sig2OverR2, 3);
    const double sig12OverR12 = pow(sig6OverR6, 2);
    const double energy = 4.0 * epsilon * (sig12OverR12 - sig6OverR6);
    
    if (r2 == 0){
        return 0;
    }
    else{
        return energy;
    }
}

__global__ void assignAtomPositions(double *dev_doublesX, double *dev_doublesY, double *dev_doublesZ, Atom *atoms, Environment *enviro){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;

    //for each atom...
    if (idx < enviro->numOfAtoms){
        atoms[idx].x = dev_doublesX[idx] * enviro->x + atoms[idx].x;
        atoms[idx].y = dev_doublesY[idx] * enviro->y + atoms[idx].y;
        atoms[idx].z = dev_doublesZ[idx] * enviro->z + atoms[idx].z;
    }
}

//generate coordinate data for the atoms
void generatePoints(Atom *atoms, Environment *enviro){
    //setup CUDA storage
    curandGenerator_t generator;
    double *devXDoubles;
    double *devYDoubles;
    double *devZDoubles;
    //double *hostDoubles;
    Atom *devAtoms;
    Environment *devEnviro;
    
    //hostDoubles = (double *) malloc(sizeof(double) * N);

    //allocate memory on device
    cudaMalloc((void**)&devXDoubles, enviro->numOfAtoms * sizeof(double));
    cudaMalloc((void**)&devYDoubles, enviro->numOfAtoms * sizeof(double));
    cudaMalloc((void**)&devZDoubles, enviro->numOfAtoms * sizeof(double));
    cudaMalloc((void**)&devAtoms, enviro->numOfAtoms * sizeof(Atom));
    cudaMalloc((void**)&devEnviro, sizeof(Environment));

    //copy local data to device
    cudaMemcpy(devAtoms, atoms, enviro->numOfAtoms * sizeof(Atom), cudaMemcpyHostToDevice);
    cudaMemcpy(devEnviro, enviro, sizeof(Environment), cudaMemcpyHostToDevice);

    //generate doubles for all coordinates
    curandCreateGenerator(&generator, CURAND_RNG_PSEUDO_DEFAULT);
    curandSetPseudoRandomGeneratorSeed(generator, (unsigned int) time(NULL));
    curandGenerateUniformDouble(generator, devXDoubles, enviro->numOfAtoms);
    curandGenerateUniformDouble(generator, devYDoubles, enviro->numOfAtoms);
    curandGenerateUniformDouble(generator, devZDoubles, enviro->numOfAtoms);
   /* 
    srand((unsigned int) time(NULL));
    for (int i = 0; i < N; i = i + 3){
        double newDouble = ((double) rand()) / ((double) (RAND_MAX));
        hostDoubles[i] = newDouble;
        newDouble = ((double) rand()) / ((double) (RAND_MAX));
        hostDoubles[i+1] = newDouble;
        newDouble = ((double) rand()) / ((double) (RAND_MAX));
        hostDoubles[i+2] = newDouble;
    }
    
    for (int i = 0; i < N; i++){
        hostDoubles[i] = 1.0;

    }
    cudaMemcpy(devDoubles, hostDoubles, N * sizeof(double), cudaMemcpyHostToDevice);
    */

    //calculate number of blocks required
    int numOfBlocks = enviro->numOfAtoms / THREADS_PER_BLOCK + (enviro->numOfAtoms % THREADS_PER_BLOCK == 0 ? 0 : 1);

    //assign the doubles to the coordinates
    assignAtomPositions <<< numOfBlocks, THREADS_PER_BLOCK >>> (devXDoubles, devYDoubles, devZDoubles, devAtoms, devEnviro);

    //copy the atoms back to host
    cudaMemcpy(atoms, devAtoms, enviro->numOfAtoms * sizeof(Atom), cudaMemcpyDeviceToHost);

    //cleanup
    curandDestroyGenerator(generator);
    cudaFree(devXDoubles);
    cudaFree(devYDoubles);
    cudaFree(devZDoubles);
    cudaFree(devAtoms);
    cudaFree(devEnviro);

    //free(hostDoubles);
}

//Calculates the energy of system using molecules
double calcEnergyWrapper(Molecule *molecules, Environment *enviro){
    
    Atom *atoms = (Atom *) malloc(sizeof(Atom) * enviro->numOfAtoms);
    int atomIndex = 0;
    for(int i = 0; i < enviro->numOfMolecules; i++){
        Molecule currentMolecule = molecules[i];
        for(int j = 0; j < currentMolecule.numOfAtoms; j++){
            atoms[atomIndex] = currentMolecule.atoms[j];
            //printf("%d, %f, %f, %f, %f, %f\n", atoms[atomIndex].id, atoms[atomIndex].x,
            //        atoms[atomIndex].y, atoms[atomIndex].z, atoms[atomIndex].sigma,
             //       atoms[atomIndex].epsilon);
            atomIndex++;
        }
    }

    return calcEnergyWrapper(atoms, enviro);
}

double calcEnergyWrapper(Atom *atoms, Environment *enviro){
    //setup CUDA storage
    double totalEnergy = 0.0;
    Atom *atoms_device;
    double *energySum_device;
    double *energySum_host;
    Environment *enviro_device;

    //calculate CUDA thread mgmt
    int N =(int) ( pow( (float) enviro->numOfAtoms,2)-enviro->numOfAtoms)/2;
    int blocks = N / THREADS_PER_BLOCK + (N % THREADS_PER_BLOCK == 0 ? 0 : 1);

    //The number of bytes of shared memory per block of
    size_t sharedSize = sizeof(double) * THREADS_PER_BLOCK;
    size_t atomSize = enviro->numOfAtoms * sizeof(Atom);
    size_t energySumSize = N * sizeof(double);
    
    //allocate memory on the device
    energySum_host = (double *) malloc(energySumSize);
    cudaMalloc((void **) &atoms_device, atomSize);
    cudaMalloc((void **) &energySum_device, energySumSize);
    cudaMalloc((void **) &enviro_device, sizeof(Environment));

    //copy data to the device
    cudaMemcpy(atoms_device, atoms, atomSize, cudaMemcpyHostToDevice);
    cudaMemcpy(enviro_device, enviro, sizeof(Environment), cudaMemcpyHostToDevice);

    calcEnergy <<<blocks, THREADS_PER_BLOCK>>>(atoms_device, enviro_device, energySum_device);
    
    cudaMemcpy(energySum_host, energySum_device, energySumSize, cudaMemcpyDeviceToHost);

    for(int i = 0; i < N; i++){
        totalEnergy += energySum_host[i];
        //printf("energySum_host[%d] = %f\n", i, energySum_host[i]);
        //printf("totalEnergy: %f\n" , totalEnergy);
    }

    //cleanup
    cudaFree(atoms_device);
    cudaFree(energySum_device);
    free(energySum_host);

    return totalEnergy;
}

__global__ void calcEnergy(Atom *atoms, Environment *enviro, double *energySum){

//need to figure out how many threads per block will be executed
// must be a power of 2
    __shared__ double cache[THREADS_PER_BLOCK];

    int cacheIndex = threadIdx.x;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;

    double lj_energy,charge_energy, fValue;

    int N =(int) ( pow( (float) enviro->numOfAtoms,2)-enviro->numOfAtoms)/2;

    if(idx < N ){
    //calculate the x and y positions in the Atom array
        int xAtom_pos, yAtom_pos;
        xAtom_pos = getXFromIndex(idx);
        yAtom_pos = getYFromIndex(xAtom_pos, idx);

        Atom xAtom, yAtom;
        xAtom = atoms[xAtom_pos];
        yAtom = atoms[yAtom_pos];

        lj_energy = calc_lj(xAtom,yAtom,*enviro);
        charge_energy = calcCharge(xAtom, yAtom, enviro);
        fValue = 1.0; //TODO: make this the proper function call when the signature is finalized
        
        energySum[idx] = fValue * (lj_energy + charge_energy);
    }
    else {
        lj_energy = 0.0;
    }


    /**
// set the cache values
cache[cacheIndex] = lj_energy;
// synchronize threads in this block
__syncthreads();
// adds 2 positions together
int i = blockDim.x/2;
while (i != 0) {
if (cacheIndex < i)
cache[cacheIndex] += cache[cacheIndex + i];
__syncthreads();
i /= 2;
}
// copy this block's sum to the enrgySums array
// at its block index postition
if (cacheIndex == 0)
energySum[blockIdx.x] = cache[0];
*/

}

__device__ double calcCharge(Atom atom1, Atom atom2, Environment *enviro){
    const double e = 1.602176565 * pow(10.f,-19.f);
 
    //calculate difference in coordinates
    double deltaX = atom1.x - atom2.x;
    double deltaY = atom1.y - atom2.y;
    double deltaZ = atom1.z - atom2.z;

    //calculate distance between atoms
    deltaX = makePeriodic(deltaX, enviro->x);
    deltaY = makePeriodic(deltaY, enviro->y);
    deltaZ = makePeriodic(deltaZ, enviro->z);

    const double r2 = (deltaX * deltaX) +
                      (deltaY * deltaY) + 
                      (deltaZ * deltaZ);
    
    const double r = sqrt(r2);

    return (atom1.charge * atom2.charge * pow(e,2) / r);
}

__device__ double calcBlending(double d1, double d2){
    return sqrt(d1 * d2);
}

//returns the molecule that contains a given atom
__device__ int getMoleculeFromAtomID(Atom a1, Molecule *molecules, Environment enviro){
    int atomId = a1.id;
    int currentIndex = enviro.numOfMolecules - 1;
    int molecId = molecules[currentIndex].id;
    while(atomId < molecId && currentIndex > 0){
        currentIndex -= 1;
        molecId = molecules[currentIndex].id;
    }
    return molecId;

}

__device__ double getFValue(Atom atom1, Atom atom2, Molecule *molecules, Environment *enviro){
    int m1 = getMoleculeFromAtomID(atom1, molecules, *enviro);
    int m2 = getMoleculeFromAtomID(atom2, molecules, *enviro);
    Molecule molec = molecules[0];
    for(int i = 0; i < enviro->numOfMolecules; i++){
        if(molecules[i].id == m1){
            molec = molecules[i];
            break;
        }
    }

    if(m1 != m2)
        return 1.0;
    else if(getDistance(atom1, atom2, molec, *enviro) >= 3)
        return 0.5;
    else
        return 0.0;
}

__device__ int getDistance(Atom atom1, Atom atom2, Molecule molecule, Environment enviro){
    //TODO
    return 3;

}

void rotateMolecule(Molecule molecule, Atom pivotAtom, double maxRotation){
    //save pivot atom coordinates because they will change
    double pivotAtomX = pivotAtom.x;
    double pivotAtomY = pivotAtom.y;
    double pivotAtomZ = pivotAtom.z;

    //translate entire molecule to place pivotAtom at origin
    for (int i = 0; i < molecule.numOfAtoms; i++){
        molecule.atoms[i].x -= pivotAtomX;
        molecule.atoms[i].y -= pivotAtomY;
        molecule.atoms[i].z -= pivotAtomZ;
    }

    srand(time(NULL));
    double dtr = PI / 180.0;

    //rotate molecule about origin
    for (int axis = 0; axis < 3; axis++){
        double rotation = ((double) rand() / RAND_MAX) * maxRotation * dtr;
        double sinrot = sin(rotation);
        double cosrot = cos(rotation);
        if (axis == 0){ //rotate about x-axis
            for (int i = 0; i < molecule.numOfAtoms; i++){
                Atom *thisAtom = &(molecule.atoms[i]);
                double oldY = thisAtom->y;
                double oldZ = thisAtom->z;
                thisAtom->y = cosrot * oldY + sinrot * oldZ;
                thisAtom->z = cosrot * oldZ - sinrot * oldY;
            }
        }
        else if (axis == 1){ //rotate about y-axis
            for (int i = 0; i < molecule.numOfAtoms; i++){
                Atom *thisAtom = &(molecule.atoms[i]);
                double oldX = thisAtom->x;
                double oldZ = thisAtom->z;
                thisAtom->x = cosrot * oldX - sinrot * oldZ;
                thisAtom->z = cosrot * oldZ + sinrot * oldX;
            }
        }
        if (axis == 2){ //rotate about z-axis
            for (int i = 0; i < molecule.numOfAtoms; i++){
                Atom *thisAtom = &(molecule.atoms[i]);
                double oldX = thisAtom->x;
                double oldY = thisAtom->y;
                thisAtom->x = cosrot * oldX + sinrot * oldY;
                thisAtom->y = cosrot * oldY - sinrot * oldX;
            }
        }
    }

    //translate entire molecule back based on original pivot point
    for (int i = 0; i < molecule.numOfAtoms; i++){
        molecule.atoms[i].x += pivotAtomX;
        molecule.atoms[i].y += pivotAtomY;
        molecule.atoms[i].z += pivotAtomZ;
    }
}

/**
  This  is currently a stub pending information from Dr. Acevedo
*/
double solventAccessibleSurfaceArea(){
    return -1.f;
}

/**
  This is currently a stub pending information from Dr. Acevedo
*/
double soluteSolventDistributionFunction(){
    return -1.f;
}

/**
  This is currently a stub pending information from Dr. Acevedo
*/
double atomAtomDistributionFunction(){
    return -1.f;
}

/**
  This is currently a stub pending information from Dr. Acevedo
*/
double solventSolventTotalEnergy(){
    return -1.f;
}

/**
  This is currently a stub pending information from Dr. Acevedo
*/
double soluteSolventTotalEnergy(){
    return -1.f;
}


#ifdef DEBUG

//these are all test wrappers for __device__ functions because they cannot be called from an outside source file.

__global__ void testCalcCharge(Atom *atoms1, Atom *atoms2, double *answers, Environment *enviro){
    int idx = threadIdx.x + blockIdx.x * blockDim.x;

    if(idx < enviro->numOfAtoms){
        answers[idx] = calcCharge(atoms1[idx], atoms2[idx], enviro);
    }
}

__global__ void testGetMoleculeFromID(Atom *atoms, Molecule *molecules,
        Environment enviros, int numberOfTests, int *answers){

    int idx = threadIdx.x + blockIdx.x * blockDim.x;

    if(idx < numberOfTests){
        answers[idx] = getMoleculeFromAtomID(atoms[idx], molecules,
                enviros);
    }
    
}

__global__ void testGetFValue(Atom *atom1List, Atom *atom2List, 
        Molecule *molecules, Environment *enviro, double *fValues, int numberOfTests){ 
    
    int idx = threadIdx.x + blockIdx.x * blockDim.x;

    if (idx < numberOfTests){
        fValues[idx] = getFValue(atom1List[idx], atom2List[idx], molecules, enviro);
    }
}

__global__ void testCalcBlending(double *d1, double *d2, double *answers, int numberOfTests){
    int idx = threadIdx.x + blockIdx.x * blockDim.x;

    if(idx < numberOfTests){
        answers[idx] = calcBlending(d1[idx], d2[idx]);
    }
}

__global__ void testMakePeriodicKernel(double *x, double *box, int n){ 
    int idx =  threadIdx.x + blockIdx.x * blockDim.x;

    if (idx < n){
        x[idx] = makePeriodic(x[idx], *box);
    }   
}

__global__ void testGetYKernel(int *xValues, int *yValues, int n){ 
    int idx =  threadIdx.x + blockIdx.x * blockDim.x;
    
    if (idx < n){
        yValues[idx] = getYFromIndex(xValues[idx], idx);
    }
}

__global__ void testGetXKernel(int *xValues, int n){
    int idx =  threadIdx.x + blockIdx.x * blockDim.x;
    
    if (idx < n){
        xValues[idx] = getXFromIndex(idx); 
    }
}

__global__ void testCalcLJ(Atom *atoms, Environment *enviro, double *energy){
    Atom atom1 = atoms[0];
    Atom atom2 = atoms[1];

    double testEnergy = calc_lj(atom1, atom2, *enviro);
    
    *energy = testEnergy;
}

__global__ void testGetDistance(Atom *atom1List, Atom *atom2List, Molecule molecule,
         Environment *enviro, int *distances, int numberOfTests){
 
    int idx = threadIdx.x + blockIdx.x * blockDim.x;

    if (idx < numberOfTests){
        distances[idx] = getDistance(atom1List[idx], atom2List[idx], molecule, *enviro);
    }    
}

#endif //DEBUG
