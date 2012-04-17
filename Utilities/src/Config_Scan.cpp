/*!\file
  \brief Class used to read and write configuration files.
  \author Alexander Luchs, Riley Spahn, Seth Wooten
 
 */
#include "Config_Scan.h"

Config_Scan::Config_Scan(string configPath){
    configpath = configPath;
}

void Config_Scan::readInConfig(){
    ifstream configscanner(configpath.c_str());
    if (! configscanner.is_open()){
        cerr << "Configuration file failed to open." << endl;
    
        return;
    }
    else {
        string line;
        int currentLine = 1;
        while (configscanner.good()){
            getline(configscanner,line);
            //assigns attributes based on line number
            switch(currentLine){
                case 2:
                    enviro.x = atof(line.c_str());
                    break;
                case 3:
                    enviro.y = atof(line.c_str());
                    break;
                case 4:
                    enviro.z = atof(line.c_str());
                    break;
                case 6:
                    enviro.temperature = atof(line.c_str());
                    break;
                case 8:
                    enviro.maxTranslation = atof(line.c_str());
                    break;
                case 10:
                    numOfSteps = atoi(line.c_str());
                    break;
                case 12:
                    enviro.numOfMolecules = atoi(line.c_str());
                    break;
                case 14:
                    oplsuaparPath = line;
                    break;
                case 16:
                    zmatrixPath = line;
                    break;
                case 18:
                    if(line.length() > 0){
                        statePath = line;
                    }
                    break;
                case 20:
                    if(line.length() > 0){
                        stateOutputPath = line;
                    }
                    break;
                case 22:
                    if(line.length() > 0){
                        pdbOutputPath = line;
                    }
                    break;
            }
            currentLine++;
        }
    }
}

Environment Config_Scan::getEnviro(){
    return enviro;
}

string Config_Scan::getConfigPath(){
    return configpath;
}


long Config_Scan::getSteps(){
    return numOfSteps;
}
    
string Config_Scan::getOplsusaparPath(){
    return oplsuaparPath;
}

string Config_Scan::getZmatrixPath(){
    return zmatrixPath;
}

string Config_Scan::getStatePath(){
    return statePath;
}

string Config_Scan::getStateOutputPath(){
    return stateOutputPath;
}

string Config_Scan::getPdbOutputPath(){
    return pdbOutputPath;
}
