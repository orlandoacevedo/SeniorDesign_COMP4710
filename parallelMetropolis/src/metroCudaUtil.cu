#include "metroCudaUtil.cuh"

void cudaAssert(const cudaError err, const char *file, const int line)
{ 
    if( cudaSuccess != err) {                                                
        fprintf(stderr, "Cuda error in file '%s' in line %i : %s.\n",        
                file, line, cudaGetErrorString(err) );
        //exit(1);
    } 
}

//create a device molecule structure.
DeviceMolecule createDeviceMolecule(int id, int atomStart, int numOfAtoms,
        int bondStart, int numOfBonds, int angleStart, int numOfAngles,
        int dihedralStart, int numOfDihedrals, int hopStart, int numOfHops){
    
    DeviceMolecule dm;
    dm.id = id;
    
    dm.atomStart = atomStart;
    dm.numOfAtoms = numOfAtoms;
    
    dm.bondStart = bondStart;
    dm.numOfBonds = numOfBonds;

    dm.angleStart = angleStart;
    dm.numOfAngles = numOfAngles;

    dm.dihedralStart = dihedralStart;
    dm.numOfDihedrals = numOfDihedrals;

    dm.hopStart = hopStart;
    dm.numOfHops = numOfHops;

    return dm;
}

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

    while(x >  box){
        x -= box;
    }
    while(x < 0){
        x += box;
    }

    return x;
}

void keepMoleculeInBox(Molecule *molecule, Environment *enviro){

    double maxX = DBL_MIN;
    double maxY = DBL_MIN;
    double maxZ = DBL_MIN;

    double minX = DBL_MAX;
    double minY = DBL_MAX;
    double minZ = DBL_MAX;

    double nudge = pow(10.0, -15.0);

    //determine extreme boundaries for molecule
    for (int i = 0; i < molecule->numOfAtoms; i++){
        double currentX = molecule->atoms[i].x;
        double currentY = molecule->atoms[i].y;
        double currentZ = molecule->atoms[i].z;

        if (currentX > maxX)
           maxX = currentX;
        else if (currentX < minX)
           minX = currentX;

        if (currentY > maxY)
            maxY = currentY;
        else if (currentY < minY)
            minY = currentY;

        if (currentZ > maxZ)
            maxZ = currentZ;
        else if (currentZ < minZ)
            minZ = currentZ;
    
    }

    bool isFullyOutX = (minX > enviro->x || maxX < 0) ? true : false;
    bool isFullyOutY = (minY > enviro->y || maxY < 0) ? true : false;
    bool isFullyOutZ = (minZ > enviro->z || maxZ < 0) ? true : false;


    //for each axis, determine if the molecule escapes the environment 
    //and wrap it around into the environment
    for (int i = 0; i < molecule->numOfAtoms; i++){
        double* currentX = &(molecule->atoms[i].x);
        double* currentY = &(molecule->atoms[i].y);
        double* currentZ = &(molecule->atoms[i].z);
        if (maxX > enviro->x){
            if (!isFullyOutX){
                *currentX += (enviro->x - minX);
            }
            *currentX = wrapBox(*currentX + nudge, enviro->x);
        }
        else if (minX < 0){
            if (!isFullyOutX)
                *currentX -= maxX;
            *currentX = wrapBox(*currentX - nudge, enviro->x);
        }

        if (maxY > enviro->y){
            if (!isFullyOutY)
                *currentY += (enviro->y - minY);
            *currentY = wrapBox(*currentY + nudge, enviro->y);
        }
        else if (minY < 0){
            if (!isFullyOutY)
                *currentY -= maxY;
            *currentY = wrapBox(*currentY - nudge, enviro->y);
        }

        if (maxZ > enviro->z){
            if (!isFullyOutZ)
                *currentZ += (enviro->z - minZ);
            *currentZ = wrapBox(*currentZ + nudge, enviro->z);
        }
        else if (minZ < 0){
            if (!isFullyOutZ)
                *currentZ -= maxZ;
            *currentZ = wrapBox(*currentZ - nudge, enviro->z);
        }
        
    }

}
//calculate Lennard-Jones energy between two atoms
__device__ double calc_lj(Atom atom1, Atom atom2, Environment enviro){
    //store LJ constants locally
    double sigma = calcBlending(atom1.sigma, atom2.sigma);
    double epsilon = calcBlending(atom1.epsilon, atom2.epsilon);
    
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
        return 0.0;
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
}

//generate coordinate data for the atoms with all molecules
void generatePoints(Molecule *molecules, Environment *enviro){
    srand(time(NULL));

    for (int i = 0; i < enviro->numOfMolecules; i++){
        double baseX = ( (double) rand() / RAND_MAX) * enviro->x;
        double baseY = ( (double) rand() / RAND_MAX) * enviro->y;
        double baseZ = ( (double) rand() / RAND_MAX) * enviro->z;
        for (int j = 0; j < molecules[i].numOfAtoms; j++){
            molecules[i].atoms[j].x += baseX;
            molecules[i].atoms[j].y += baseY;
            molecules[i].atoms[j].z += baseZ;
        }

        keepMoleculeInBox(&(molecules[i]), enviro);
    }
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

    return calcEnergyWrapper(atoms, enviro, molecules);
}

double calcEnergyWrapper(Atom *atoms, Environment *enviro, Molecule *molecules){
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
    //size_t sharedSize = sizeof(double) * THREADS_PER_BLOCK;
    
    size_t atomSize = enviro->numOfAtoms * sizeof(Atom);
    size_t energySumSize = N * sizeof(double);
    
    //allocate memory on the device
    energySum_host = (double *) malloc(energySumSize);
    cudaMalloc((void **) &atoms_device, atomSize);
    cudaMalloc((void **) &energySum_device, energySumSize);
    cudaMalloc((void **) &enviro_device, sizeof(Environment));

    //copy data to the device
    cudaErrorCheck(cudaMemcpy(atoms_device, atoms, atomSize, cudaMemcpyHostToDevice));
    cudaErrorCheck(cudaMemcpy(enviro_device, enviro, sizeof(Environment), cudaMemcpyHostToDevice));

    calcEnergy <<<blocks, THREADS_PER_BLOCK>>>(atoms_device, enviro_device, energySum_device);
    
    cudaErrorCheck(cudaMemcpy(energySum_host, energySum_device, energySumSize, cudaMemcpyDeviceToHost));

    for(int i = 0; i < N; i++){

        int c = -2 * i;
        int discriminant = 1 - 4 * c;
        int qv = (-1 + sqrtf(discriminant)) / 2;
        int atomXid = qv + 1;
        
        int atomYid =  i - (atomXid * atomXid - atomXid) / 2;

        if (isnan(energySum_host[i]) != 0 || isinf(energySum_host[i]) != 0){
            energySum_host[i] = calcEnergyOnHost(atoms[atomXid], atoms[atomYid], enviro);
        }
        
        //cout << "EnergySum[" << i << "]: " << energySum_host[i] << " (before)" << endl;
        
        if (molecules != NULL){
            energySum_host[i] = energySum_host[i] * getFValueHost(atoms[atomXid], atoms[atomYid], molecules, enviro); 
        }
        
        //cout << "EnergySum[" << i << "]: " << energySum_host[i] << " (after)" << endl;
        totalEnergy += energySum_host[i];
        //cout << "totalEnergy: " << totalEnergy << endl;

    }

    //cleanup
    cudaFree(atoms_device);
    cudaFree(energySum_device);
    free(energySum_host);

    return totalEnergy;
}

double calcEnergyOnHost(Atom atom1, Atom atom2, Environment *enviro){
    const double e = 332.06;

    double sigma = sqrt(atom1.sigma * atom2.sigma);
    double epsilon = sqrt(atom1.epsilon * atom2.epsilon);
    
    double deltaX = atom1.x - atom2.x;
    double deltaY = atom1.y - atom2.y;
    double deltaZ = atom1.z - atom2.z;
  
    deltaX = make_periodic(deltaX, enviro->x);
    deltaY = make_periodic(deltaY, enviro->y);
    deltaZ = make_periodic(deltaZ, enviro->z);

    double r2 = (deltaX * deltaX) +
                      (deltaY * deltaY) + 
                      (deltaZ * deltaZ);

    double r = sqrt(r2);

    double sig2OverR2 = pow(sigma, 2) / r2;
    double sig6OverR6 = pow(sig2OverR2, 3);
    double sig12OverR12 = pow(sig6OverR6, 2);
    double lj_energy = 4.0 * epsilon * (sig12OverR12 - sig6OverR6);

    double charge_energy = (atom2.charge * atom1.charge * e) / r;
    
    if (r2 == 0.0){
        lj_energy = 0.0;
        charge_energy = 0.0;
    }

    return (lj_energy + charge_energy);

}

__global__ void calcEnergy(Atom *atoms, Environment *enviro, double *energySum){

//need to figure out how many threads per block will be executed
// must be a power of 2
//    __shared__ double cache[THREADS_PER_BLOCK];

    //int cacheIndex = threadIdx.x;
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

        if(xAtom.sigma < 0 || xAtom.epsilon < 0 || yAtom.sigma < 0 || yAtom.epsilon < 0){
            energySum[idx] = 0.0;
        }
        else{
            lj_energy = calc_lj(xAtom,yAtom,*enviro);
            charge_energy = calcCharge(xAtom, yAtom, enviro);
            fValue = 1.0; //TODO: Fix after fValue calculation is moved to device
            
            energySum[idx] = fValue * (lj_energy + charge_energy);
        }
    }
    else {
        energySum[idx] = 0.0;
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
    const double e = 332.06;
 
    //calculate difference in coordinates
    double deltaX = atom1.x - atom2.x;
    double deltaY = atom1.y - atom2.y;
    double deltaZ = atom1.z - atom2.z;

    //calculate distance between atoms
    deltaX = makePeriodic(deltaX, enviro->x);
    deltaY = makePeriodic(deltaY, enviro->y);
    deltaZ = makePeriodic(deltaZ, enviro->z);

    double r2 = (deltaX * deltaX) +
                      (deltaY * deltaY) + 
                      (deltaZ * deltaZ);
    
    double r = sqrt(r2);


    if (r == 0.0){
        return 0.0;
    }
    else{
        return (atom1.charge * atom2.charge * e) / r;
    }
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
	/**
      This line gives a warning about not knowing what memory space it points to
      because CUDA has multiple memory spaces.  This should not be a problem because
      it defaults to global memory space which is correct in this case.  May want
      to look into it in the future.
    */
    else{
        int hops = hopGE3(atom1.id, atom2.id, molecules[m1]);
        if (hops == 3)
            return 0.5;
        else if (hops > 3)
            return 1.0;
        else
            return 0.0;
    } 
}

__device__ int hopGE3(int atom1, int atom2, Molecule molecule){
    for(int x=0; x< molecule.numOfHops; x++){
		      Hop myHop = molecule.hops[x];
				if((myHop.atom1==atom1 && myHop.atom2==atom2) || (myHop.atom1==atom2 && myHop.atom2==atom1))
				    return myHop.hop;
	 }
	 return 0;
}

//returns the molecule that contains a given atom
Molecule* getMoleculeFromAtomIDHost(Atom a1, Molecule *molecules, Environment enviro){
    int atomId = a1.id;
    int currentIndex = enviro.numOfMolecules - 1;
    int molecId = molecules[currentIndex].id;
    while(atomId < molecId && currentIndex > 0){
        currentIndex -= 1;
        molecId = molecules[currentIndex].id;
    }
    return &molecules[currentIndex];

}

double getFValueHost(Atom atom1, Atom atom2, Molecule *molecules, Environment *enviro){
    Molecule *m1 = getMoleculeFromAtomIDHost(atom1, molecules, *enviro);
    Molecule *m2 = getMoleculeFromAtomIDHost(atom2, molecules, *enviro);
    Molecule molec = molecules[0];
    for(int i = 0; i < enviro->numOfMolecules; i++){
        if(molecules[i].id == m1->id){
            molec = molecules[i];
            break;
        }
    }

    if(m1->id != m2->id)
        return 1.0;
	else{
        int hops = hopGE3Host(atom1.id, atom2.id, *m1);
        if (hops == 3)
            return 0.5;
        else if (hops > 3)
            return 1.0;
        else
            return 0.0;
     }
}

int hopGE3Host(int atom1, int atom2, Molecule molecule){
    for(int x=0; x< molecule.numOfHops; x++){
		      Hop myHop = molecule.hops[x];
				if((myHop.atom1==atom1 && myHop.atom2==atom2) ||
                        (myHop.atom1 == atom2 && myHop.atom2 == atom1) )
				    return myHop.hop;
	 }
	 return 0;
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
        double rotation = ((double) rand() / (double) RAND_MAX) * maxRotation * dtr;
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

//Implementation of the copy to device function
    /**
      It might be better if we do this where it just copies.
      This might be better as a create molecule on device function
    */
void moleculeDeepCopyToDevice(DeviceMolecule *molec_d, Molecule *molec_h,
        int numOfMolecules, Atom *atoms_d, Bond *bonds_d, Angle *angles_d,
        Dihedral *dihedrals_d, Hop *hops_d){
    
    int atomCount = 0;
    int bondCount = 0;
    int angleCount = 0;
    int dihedralCount = 0;
    int hopCount = 0;

    for(int i = 0; i < numOfMolecules; i++){
        Molecule m = molec_h[i];
        
        atomCount += m.numOfAtoms;
        bondCount += m.numOfBonds;
        angleCount += m.numOfAngles;
        dihedralCount += m.numOfDihedrals;
        hopCount += m.numOfHops;
    }
    printf("TOTALS:\n");
    printf("Molecules: %d\n", numOfMolecules);
    printf("Atoms: %d\n", atomCount);
    printf("Bonds: %d\n", bondCount);
    printf("Angles: %d\n", angleCount);
    printf("Dihedrals: %d\n", dihedralCount);
    printf("Hops: %d\n", hopCount);
    //size of each array
    size_t molecSize = sizeof(DeviceMolecule) * numOfMolecules;
    size_t atomSize = sizeof(Atom) * atomCount;
    size_t bondSize = sizeof(Bond) * bondCount;
    size_t angleSize = sizeof(Angle) * angleCount;
    size_t dihedralSize = sizeof(Dihedral) * dihedralCount;
    size_t hopSize = sizeof(Hop) * hopCount;
   
    //create arrays to hold data on host
    DeviceMolecule *dMolec_h = (DeviceMolecule *)malloc(molecSize);
    Atom *atoms_h = (Atom *)malloc(atomSize);
    Bond *bonds_h = (Bond *)malloc(bondSize);
    Angle *angles_h = (Angle *)malloc(angleSize);
    Dihedral *dihedrals_h = (Dihedral *)malloc(dihedralSize);
    Hop *hops_h = (Hop *)malloc(hopSize);

    int atomIndex = 0;
    int bondIndex = 0;
    int angleIndex = 0;
    int dihedralIndex = 0;
    int hopIndex = 0;
    printf("Creating large arrays.\n");
    //split fields into their own arrays
    for(int i = 0; i < numOfMolecules; i++){
        Molecule m = molec_h[i];
        //Create device molecule
        dMolec_h[i] = createDeviceMolecule(m.id, atomIndex, m.numOfAtoms,
                bondIndex, m.numOfBonds, angleIndex, m.numOfAngles,
                dihedralIndex, m.numOfDihedrals, hopIndex, m.numOfHops);
        printf("--Molecule %d--\n", dMolec_h[i].id);
        printf("numOfAtoms: %d\n", m.numOfAtoms);
        printf("numOfBonds: %d\n", m.numOfBonds);
        printf("numOfAngles: %d\n", m.numOfAngles);
        printf("numOfDihedrals: %d\n", m.numOfDihedrals);
        printf("numOfHops: %d\n", m.numOfHops);
        
        //assign atoms
        printf("--Atoms--\n");
        for(int j = 0; j < m.numOfAtoms; j++){
            atoms_h[atomIndex] = m.atoms[j];
            printf("atoms_h[%d]\n", atomIndex);
            printf("id: %d | x: %f | y: %f | z: %f\n", atoms_h[atomIndex].id, atoms_h[atomIndex].x, atoms_h[atomIndex].y, atoms_h[atomIndex].z);
            atomIndex++;
        }

        //assign bonds
        printf("--Bonds--\n");
        for(int j = 0; j < m.numOfBonds; j++){
            bonds_h[bondIndex] = m.bonds[j];
            printf("bonds_h[%d]\n", bondIndex);
            printf("atom1: %d | atom2: %d | distance: %f\n", bonds_h[bondIndex].atom1, bonds_h[bondIndex].atom2, bonds_h[bondIndex].distance);
            bondIndex++;
        }
        
        //assign angles
        printf("--Angles--\n");
        for(int j = 0; j < m.numOfAngles; j++){
            angles_h[angleIndex] = m.angles[j];
            printf("angles_h[%d]\n", angleIndex);
            printf("atom1: %d | atom2: %d | value: %f\n", angles_h[angleIndex].atom1, angles_h[angleIndex].atom2, angles_h[angleIndex].value);
            angleIndex++;
        }
        
        //assign dihedrals
        printf("--Dihedrals--\n");
        for(int j = 0; j < m.numOfDihedrals; j++){
            dihedrals_h[dihedralIndex] = m.dihedrals[j];
            printf("dihedrals_h[%d]\n", dihedralIndex);
            printf("atom1: %d | atom2: %d | value: %f\n", dihedrals_h[dihedralIndex].atom1, dihedrals_h[dihedralIndex].atom2, dihedrals_h[dihedralIndex].value);
            dihedralIndex++;
        }

        //assing hops
        printf("--Hops--\n");
        for(int j = 0; j < m.numOfHops; j++){
            hops_h[hopIndex] = m.hops[j];
            printf("hops_h[%d]\n", hopIndex);
            printf("atom1: %d | atom2: %d | hop: %d\n", hops_h[hopIndex].atom1, hops_h[hopIndex].atom2, hops_h[hopIndex].hop);
            hopIndex++;
        }
    }

    //transfer data
    /*printf("Before copy ID = %d\n", dMolec_h[0].id);
    printf("atom id = %d\n", atoms_h[0].id);
    printf("atom x = %f\n", atoms_h[0].x);
    printf("Bond atom1 = %d\n", bonds_h[0].atom1);
    printf("Angle atom1 = %d\n", angles_h[0].atom1);
    printf("Dihedral atom1 = %d\n", dihedrals_h[0].atom1);
    printf("Hop atom1 = %d\n", hops_h[0].atom1);
   */ 
    
    cudaErrorCheck(cudaMemcpy(molec_d, dMolec_h, molecSize, cudaMemcpyHostToDevice));
    cudaErrorCheck(cudaMemcpy(atoms_d, atoms_h, atomSize, cudaMemcpyHostToDevice));
    cudaErrorCheck(cudaMemcpy(bonds_d, bonds_h, bondSize, cudaMemcpyHostToDevice));
    cudaErrorCheck(cudaMemcpy(angles_d, angles_h, angleSize, cudaMemcpyHostToDevice));
    cudaErrorCheck(cudaMemcpy(dihedrals_d, dihedrals_h, dihedralSize, cudaMemcpyHostToDevice));
    cudaErrorCheck(cudaMemcpy(hops_d, hops_h, hopSize, cudaMemcpyHostToDevice));
 
    DeviceMolecule * tempDM = (DeviceMolecule *)malloc(molecSize);
    Atom *tempA = (Atom *)malloc(atomSize);
    Bond *tempB = (Bond *)malloc(bondSize);
    Angle *tempAng = (Angle *)malloc(angleSize);
    Dihedral *tempD = (Dihedral *)malloc(dihedralSize);
    Hop *tempH = (Hop *)malloc(hopSize);
    
    cudaMemcpy(tempDM, molec_d, molecSize, cudaMemcpyDeviceToHost);
    cudaMemcpy(tempA, atoms_d, atomSize, cudaMemcpyDeviceToHost);
    cudaMemcpy(tempB, bonds_d, bondSize, cudaMemcpyDeviceToHost);
    cudaMemcpy(tempAng, angles_d, angleSize, cudaMemcpyDeviceToHost);
    cudaMemcpy(tempD, dihedrals_d, dihedralSize, cudaMemcpyDeviceToHost);
    cudaMemcpy(tempH, hops_d, hopSize, cudaMemcpyDeviceToHost);
    
    printf("Molecules Written Back.\n");
    atomIndex = 0;
    bondIndex = 0;
    angleIndex = 0;
    dihedralIndex = 0;
    hopIndex = 0;
    for(int i = 0; i < numOfMolecules; i++){
        Molecule m = molec_h[i];
        printf("--Molecule %d--\n", m.id);
        printf("numOfAtoms: %d\n", m.numOfAtoms);
        printf("numOfBonds: %d\n", m.numOfBonds);
        printf("numOfAngles: %d\n", m.numOfAngles);
        printf("numOfDihedrals: %d\n", m.numOfDihedrals);
        printf("numOfHops: %d\n", m.numOfHops);
        printf("--Atoms--\n");
        for(int j = 0; j < m.numOfAtoms; j++){
            printf("tempA[%d]\n", atomIndex);
            printf("id: %d | x: %f | y: %f | z: %f\n", tempA[atomIndex].id, tempA[atomIndex].x, tempA[atomIndex].y, tempA[atomIndex].z);
            atomIndex++;
        }

        printf("--Bonds--\n");
        for(int j = 0; j < m.numOfBonds; j++){
            printf("tempB[%d]\n", bondIndex);
            printf("atom1: %d | atom2: %d | distance: %f\n", tempB[bondIndex].atom1, tempB[bondIndex].atom2, tempB[bondIndex].distance);
            bondIndex++;
        }
        
        printf("--Angles--\n");
        for(int j = 0; j < m.numOfAngles; j++){
            printf("tempAng[%d]\n", angleIndex);
            printf("atom1: %d | atom2: %d | value: %f\n", tempAng[angleIndex].atom1, tempAng[angleIndex].atom2, tempAng[angleIndex].value);
            angleIndex++;
        }
        
        printf("--Dihedrals--\n");
        for(int j = 0; j < m.numOfDihedrals; j++){
            printf("tempD[%d]\n", dihedralIndex);
            printf("atom1: %d | atom2: %d | value: %f\n", tempD[dihedralIndex].atom1, tempD[dihedralIndex].atom2, tempD[dihedralIndex].value);
            dihedralIndex++;
        }

        printf("--Hops--\n");
        for(int j = 0; j < m.numOfHops; j++){
            printf("tempH[%d]\n", hopIndex);
            printf("atom1: %d | atom2: %d | hop: %f\n", tempH[hopIndex].atom1, tempH[hopIndex].atom2, tempH[hopIndex].hop);
            hopIndex++;
        }
    }
    
/*
    printf("After copy ID = %d\n", tempDM[0].id);
    printf("copy ID2 = %d\n", tempDM[1].id);
    printf("atom2 id = %d\n", tempA[0].x);
    printf("atom2 id = %d\n", tempA[1].x);
    printf("Bond atom2 = %d\n", tempB[0].atom2);
    printf("Angle atom2 = %d\n", tempAng[0].atom2);
    printf("Dihedral atom2 = %d\n", tempD[0].atom2);
    printf("Hop atom2 = %d\n", tempH[0].atom2);
*/

    free(dMolec_h);
    free(atoms_h);
    free(bonds_h);
    free(angles_h);
    free(dihedrals_h);
    free(hops_h);
}

void moleculeDeepCopyToHost(Molecule *molec_h, DeviceMolecule *molec_d,
        int numOfMolecules,Atom *atoms_d, Bond *bonds_d, Angle *angles_d,
        Dihedral *dihedrals_d, Hop *hops_d){
   
    size_t molecSize = sizeof(DeviceMolecule) * numOfMolecules;
    DeviceMolecule *dMolec_h = (DeviceMolecule *)malloc(molecSize);
    cudaErrorCheck(cudaMemcpy(dMolec_h, molec_d, molecSize, cudaMemcpyDeviceToHost));

    int atomCount = 0;
    int bondCount = 0;
    int angleCount = 0;
    int dihedralCount = 0;
    int hopCount = 0;
    
    for(int i = 0; i < numOfMolecules; i++){
        DeviceMolecule m = dMolec_h[i];

        //assign correct fields
        printf("ID = %d\n", molec_h[i].id);
        molec_h[i].id = m.id;
        molec_h[i].numOfAtoms = m.numOfAtoms;
        molec_h[i].numOfBonds = m.numOfBonds;
        molec_h[i].numOfAngles = m.numOfAngles;
        molec_h[i].numOfDihedrals = m.numOfDihedrals;
        molec_h[i].numOfHops = m.numOfHops;
        printf("ID = %d\n", molec_h[i].id);

        atomCount += m.numOfAtoms;
        bondCount += m.numOfBonds;
        angleCount += m.numOfAngles;
        dihedralCount += m.numOfDihedrals;
        hopCount += m.numOfHops;
    }
    size_t atomSize = sizeof(Atom) * atomCount;
    size_t bondSize = sizeof(Bond) * bondCount;
    size_t angleSize = sizeof(Angle) * angleCount;
    size_t dihedralSize = sizeof(Dihedral) * dihedralCount;
    size_t hopSize = sizeof(Hop) * hopCount;
    
    Atom *atoms_h = (Atom *)malloc(atomSize);
    Bond *bonds_h = (Bond *)malloc(bondSize);
    Angle *angles_h = (Angle *)malloc(angleSize);
    Dihedral *dihedrals_h = (Dihedral *)malloc(dihedralSize);
    Hop *hops_h = (Hop *)malloc(hopSize);

    cudaErrorCheck(cudaMemcpy(atoms_h, atoms_d, atomSize, cudaMemcpyDeviceToHost));
    cudaErrorCheck(cudaMemcpy(bonds_h, bonds_d, bondSize, cudaMemcpyDeviceToHost));
    cudaErrorCheck(cudaMemcpy(angles_h, angles_d, angleSize, cudaMemcpyDeviceToHost));
    cudaErrorCheck(cudaMemcpy(dihedrals_h, dihedrals_d, dihedralSize, cudaMemcpyDeviceToHost));
    cudaErrorCheck(cudaMemcpy(hops_h, hops_d, hopSize, cudaMemcpyDeviceToHost));


    for(int i = 0; i < numOfMolecules; i++){
        DeviceMolecule dm = dMolec_h[i];
        printf("DeviceMolecule:\n");
        printf("id = %d\n", dm.id); 
        printf("numOfAtoms: %d\n", dm.numOfAtoms);
        printf("numOfBonds: %d\n", dm.numOfBonds);
        printf("numOfAngles: %d\n", dm.numOfAngles);
        printf("numOfDihedrals: %d\n", dm.numOfDihedrals);
        printf("numOfHops: %d\n", dm.numOfHops);
        
        printf("atomStart: %d\n", dm.atomStart);
        printf("bondStart: %d\n", dm.bondStart);
        printf("angleStart: %d\n", dm.angleStart);
        printf("dihedralStart: %d\n", dm.dihedralStart);
        printf("hopStart: %d\n", dm.hopStart);
       
        
        Molecule m = molec_h[i];
        //atoms
        for(int j = 0; j < m.numOfAtoms; j++){
            molec_h[i].atoms[j] = atoms_h[j + dm.atomStart];
        }

        //bonds
        for(int j = 0; j < m.numOfBonds; j++){
            molec_h[i].bonds[j] = bonds_h[j + dm.bondStart];
        }
        //angles
        for(int j = 0; j < m.numOfAngles; j++){
            molec_h[i].angles[j] = angles_h[j + dm.angleStart];
        }
        //dihedrals
        for(int j = 0; j < m.numOfDihedrals; j++){
            molec_h[i].dihedrals[j] = dihedrals_h[j + dm.dihedralStart];
        }
        //hops
        for(int j = 0; j < m.numOfHops; j++){
            molec_h[i].hops[j] = hops_h[j + dm.hopStart];
        }

    }
    
    free(atoms_h);
    free(bonds_h);
    free(angles_h);
    free(dihedrals_h);
    free(hops_h);
    free(dMolec_h);
    
}


void freeMoleculeOnDevice(DeviceMolecule *molec_d,
        Atom *atoms_d, Bond *bonds_d, Angle *angles_d,
        Dihedral *dihedrals_d, Hop *hops_d){
    
}

//Allocates needed memory for the molecule on the device
void allocateOnDevice(Molecule *molec_h, DeviceMolecule *molec_d,
        int numOfMolecules,Atom *atoms_d, Bond *bonds_d, Angle *angles_d,
        Dihedral *dihedrals_d, Hop *hops_d){

    //find the total size of the smaller arrays;
    int atomCount = 0;
    int bondCount = 0;
    int angleCount = 0;
    int dihedralCount = 0;
    int hopCount = 0;
    for(int i = 0; i < numOfMolecules; i++){
        Molecule m = molec_h[i];
                
        atomCount += m.numOfAtoms;
        bondCount += m.numOfBonds;
        angleCount += m.numOfAngles;
        dihedralCount += m.numOfDihedrals;
        hopCount += m.numOfHops;

    }
    //find the size of each array
    size_t molecSize = sizeof(DeviceMolecule) * numOfMolecules;
    size_t atomSize = sizeof(Atom) * atomCount;
    size_t bondSize = sizeof(Bond) * bondCount;
    size_t angleSize = sizeof(Angle) * angleCount;
    size_t dihedralSize = sizeof(Dihedral) * dihedralCount;
    size_t hopSize = sizeof(Hop) * hopCount;

    cudaMalloc((void **) &molec_d, molecSize);
    cudaMalloc((void **) &atoms_d, atomSize);
    cudaMalloc((void **) &bonds_d, bondSize);
    cudaMalloc((void **) &angles_d, angleSize);
    cudaMalloc((void **) &dihedrals_d, dihedralSize);
    cudaMalloc((void **) &hops_d, hopSize);
}
__global__ void freeArrays(Molecule *molecules, int numOfMolecules){
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    
    if(idx < numOfMolecules){
        free(molecules[idx].atoms);
        free(molecules[idx].bonds);
        free(molecules[idx].angles);
        free(molecules[idx].dihedrals);
        free(molecules[idx].hops);
    }
}

__global__ void allocateArrays(Molecule *molecules, int numOfMolecules){
    int idx = threadIdx.x + blockIdx.x * blockDim.x;

    if(idx < numOfMolecules){
        size_t atomSize = sizeof(Atom) * molecules[idx].numOfAtoms;
        molecules[idx].atoms = (Atom *)malloc(atomSize);
        
        size_t bondSize = sizeof(Bond) * molecules[idx].numOfBonds;
        molecules[idx].bonds = (Bond *)malloc(bondSize);
        
        size_t angleSize = sizeof(Angle) * molecules[idx].numOfAngles;
        molecules[idx].angles = (Angle *)malloc(angleSize);
        
        size_t dihedralSize = sizeof(Dihedral) * molecules[idx].numOfDihedrals;
        molecules[idx].dihedrals = (Dihedral *)malloc(dihedralSize);
        
        size_t hopSize = sizeof(Hop) * molecules[idx].numOfHops;
        molecules[idx].hops = (Hop *)malloc(hopSize);
    }

}

//Can easily be optimized.  Wanted it right first.
__global__ void assignArrays(Molecule *molecules, Atom *atoms, Bond *bonds, Angle *angles,
        Dihedral *dihedrals, Hop *hops, int numOfMolecules, int maxAtoms, int maxBonds, int maxAngles,
        int maxDihedrals, int maxHops){
    int idx = threadIdx.x + blockIdx.x * blockDim.x;

    if(idx < numOfMolecules){
        int atomIndex = idx * maxAtoms;
        int bondIndex = idx * maxBonds;
        int angleIndex = idx * maxAngles;
        int dihedralIndex = idx * maxDihedrals;
        int hopIndex = idx * maxHops;
        for(int i = 0; i < molecules[idx].numOfAtoms; i++){
            molecules[idx].atoms[i] = atoms[i + atomIndex];
        }
        for(int i = 0; i < molecules[idx].numOfBonds; i++){
            molecules[idx].bonds[i] = bonds[i + bondIndex];
        }
        for(int i = 0; i < molecules[idx].numOfAngles; i++){
            molecules[idx].angles[i] = angles[i + angleIndex];
        }
        for(int i = 0; i < molecules[idx].numOfDihedrals; i++){
            molecules[idx].dihedrals[i] = dihedrals[i + dihedralIndex];
        }
        for(int i = 0; i < molecules[idx].numOfHops; i++){
            molecules[idx].hops[i] = hops[i + hopIndex];
        }
    }
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

#endif //DEBUG
