classdef MatRad_MCsquareBaseData
%MatRad_MCsquareBaseData Maps the matRad base data to MCsquare base data /
%phase space file
%
%
%
% References
%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Copyright 2019 the matRad development team. 
% 
% This file is part of the matRad project. It is subject to the license 
% terms in the LICENSE file found in the top-level directory of this 
% distribution and at https://github.com/e0404/matRad/LICENSES.txt. No part 
% of the matRad project, including this file, may be copied, modified, 
% propagated, or distributed except according to the terms contained in the 
% LICENSE file.
%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    properties
        machine         %matRad base data machine struct
        bdl_path = ''   %stores path to generated file
        nozzleToIso     %Nozzle to Isocenter Distance
        smx             %Scanning magnet X to isocenter Distance
        smy             %Scanning magnet y to isocenter Distance        
        mcSquareData    %MCsquare Phase space data struct
        selectedFocus   %array containing selected focus indices per energy
    end
    
    properties (SetAccess = private)
        stfCompressed   
        problemSigma
        dataTable       %Optical beam parameter table used for BDL generation
        energyIndex     %Indices of calculated energies
    end
    
    methods
        function obj = MatRad_MCsquareBaseData(machine,stf)
            %MatRad_MCsquareBaseData Construct an instance of the MCsquare
            %Base data format using a focus index
            
            %stfCompressed states whether mcSquareData are calculated for
            %all energies (false) or only for energies which exist in given
            %stf. If function is called without stf stfCompressed = false.
            if nargin < 2
                obj.stfCompressed = false;
            else
                obj.stfCompressed = true;
            end
            
            obj.machine = machine;
            obj.problemSigma = false;
            obj.selectedFocus = ones(numel(machine.data),1) * NaN;
            
            if isfield(machine.meta,'BAMStoIsoDist')
                obj.nozzleToIso = machine.meta.BAMStoIsoDist;
            else
                warning('No information on BAMS to isocenter distance. Using generic value of 500mm');
                obj.nozzleToIso = 500;
            end
            
            SAD = machine.meta.SAD;
            
            obj.smx = SAD;
            obj.smy = SAD;
            
            obj.mcSquareData = [];
            
            %select needed energies and according focus indices by using stf         
            if obj.stfCompressed
                plannedEnergies     = [stf.ray(:).energy];
                focusIndex          = [stf.ray(:).focusIx];
                [~, ind]            = unique(plannedEnergies);
                plannedEnergies     = plannedEnergies(ind);
                focusIndex          = focusIndex(ind);
                [~ ,obj.energyIndex, ~] = intersect([machine.data(:).energy],plannedEnergies);
            
            %if no stf was refered all energies are chosen, while setting
            %the focus index for all energies to preliminary 1
            else
                plannedEnergies = [machine.data(:).energy];
                focusIndex = ones(size(plannedEnergies));
                [~ ,obj.energyIndex, ~] = intersect([machine.data(:).energy],plannedEnergies);
            end
            
            obj.selectedFocus(obj.energyIndex) = focusIndex;
             
            count = 1;
            for i = obj.energyIndex'
                
                %look up whether MonteCarlo data are already present in 
                %machine file , if so do not recalculate
                if isfield(machine.data(i),'mcSquareData')
                    if (isempty(machine.data(i).mcSquareData) == 0)
                        obj.mcSquareData = [obj.mcSquareData, machine.data(i).mcSquareData];
                        count = count + 1;
                        continue;
                    end
                end
                
                
                %calculate mcSquareData for given energy and every focus
                %index
                tmp = [];
                for j = 1:size(machine.data(i).initFocus.sigma,1)
                    
                    tmp = [tmp; obj.fitBeamOpticsForEnergy(i, j)];
                end
                
                obj.mcSquareData = [obj.mcSquareData, tmp];
                
                count = count + 1;
            end
            
            %throw out warning if there was a problem in calculating the
            %width of the Bragg peak in obj.fitBeamOpticsForEnergy
            if obj.problemSigma
                warning('Calculation of FWHM of bragg peak in base data not possible! Using simple approximation for energy spread');
            end
            
        end
        
        function mcData = fitBeamOpticsForEnergy(obj,energyIx, focusIndex)
            %function to calculate beam optics used by mcSquare for given
            %energy
            
            i = energyIx;

            mcData.NominalEnergy = obj.machine.data(energyIx).energy;             

            newDepths = linspace(0,obj.machine.data(i).depths(end),numel(obj.machine.data(i).depths) * 100);
            newDose   = interp1(obj.machine.data(i).depths, obj.machine.data(i).Z, newDepths, 'spline');       

            %find FWHM w50 of bragg peak
            [maxV, maxI] = max(newDose);
            [~, r80ind] = min(abs(newDose(maxI:end) - 0.8 * maxV));
            r80ind = r80ind - 1;
            r80 = interp1(newDose(maxI + r80ind - 1:maxI + r80ind + 1), ...
                             newDepths(maxI + r80ind - 1:maxI + r80ind + 1), 0.8 * maxV) ...
                           + obj.machine.data(i).offset;


            [~, d50rInd] = min(abs(newDose(maxI:end) - 0.5 * maxV));
            d50rInd = d50rInd - 1;
            d50_r = interp1(newDose(maxI + d50rInd - 1:maxI + d50rInd + 1), ...
                                    newDepths(maxI + d50rInd - 1:maxI + d50rInd + 1), 0.5 * maxV);

            array1 = newDepths(maxI-round(d50rInd):maxI+d50rInd);
            array2 = newDose(maxI-round(d50rInd):maxI+d50rInd);  

            gauss = @(x, a, sigma, b) a * exp(- (x - b).^2 / (2*sigma^2));

            funcs.objective = @(p) sum((gauss(array1, p(1), p(2),p(3)) - array2).^2);

            funcs.gradient = @(p) [ sum(2 * (p(1) * exp(- (array1 - p(3)).^2 / (2 * p(2)^2)) - array2) ...
                                                    .* exp(- (array1 - p(3)).^2 / (2 * p(2)^2)));
                                    sum(2 * (p(1) * exp(- (array1 - p(3)).^2 / (2 * p(2)^2)) - array2) ...
                                                    .* p(1) .* exp(- (array1 - p(3)).^2 / (2 * p(2)^2)) .* (array1 - p(3)).^2 / p(2)^3)
                                    sum(2 * (p(1) * exp(- (array1 - p(3)).^2 / (2 * p(2)^2)) - array2) ...
                                                    .* p(1) .* exp(- (array1 - p(3)).^2 / (2 * p(2)^2)) .* 2 .* (array1 - p(3)) / (2 * p(2)^2))];

            options.lb = [0,  0, 0];
            options.ub = [ Inf, Inf, Inf];
            options.ipopt.limited_memory_update_type = 'bfgs';
            options.ipopt.hessian_approximation = 'limited-memory';
            options.ipopt.print_level = 1;

            start = [maxV, 2 * d50_r, newDepths(maxI)];
            [fitResult, ~] = ipopt (start, funcs, options);
            sigmaBragg = fitResult(2);
            
            %{            
            Fit to spreadData in dependence of sigmaBragg and energy:
            x = energy; y = sigmaBragg;
            f(x,y) = p00 + p10*x + p01*y + p20*x^2 + p11*x*y + p02*y^2
            Coefficients (with 95% confidence bounds):
                p00 =      0.4065  (-0.9749, 1.788)
                p10 =   -0.006595  (-0.03623, 0.02305)
                p01 =      0.4658  (-0.2941, 1.226)
                p20 =   0.0001436  (8.193e-05, 0.0002052)
                p11 =    -0.01266  (-0.02009, -0.005244)
                p02 =      0.2373  (-0.01207, 0.4868)
            %}
            eSpread = @(E, sigma) 0.4065 - 0.006595 * E + 0.4658 * sigma + 0.0001436 * E^2 - 0.01266 * E * sigma + 0.2373 * sigma^2;


            %calculate mean energy according to the mcSquare documentation
            %using the 80% dose range
            mcData.MeanEnergy = exp(3.464048 + 0.561372013*log(r80/10) - 0.004900892*log(r80/10)^2+0.001684756748*log(r80/10)^3); 

            mcData.EnergySpread = eSpread(mcData.NominalEnergy, sigmaBragg);
            

            %calculate geometric distances and extrapolate spot size at nozzle
            SAD = obj.machine.meta.SAD;
            z     = -(obj.machine.data(i).initFocus.dist(focusIndex,:) - SAD);
            sigmaSq = obj.machine.data(i).initFocus.sigma(focusIndex,:).^2;

            %fit Courant-Synder equation to data using ipopt, formulae
            %given in mcSquare documentation
            sigmaNull = sqrt(interp1(z,sigmaSq,0));

            qRes = @(rho, sigmaT) (sigmaSq -  (sigmaNull^2 - 2*sigmaNull*rho*sigmaT.*z + sigmaT^2.*z.^2));

            funcs.objective = @(x) sum(qRes(x(1), x(2)).^2);
            funcs.gradient  = @(x) [  2 * sum(qRes(x(1), x(2)) .* (2 * sigmaNull * x(2) * z)); 
                                      2 * sum(qRes(x(1), x(2)) .* (2 * sigmaNull * x(1) * z  - 2 * x(2) * z.^2))];     

            options.lb = [-0.99, -Inf];
            options.ub = [ 0.99,  Inf];

            options.ipopt.hessian_approximation = 'limited-memory';
            options.ipopt.limited_memory_update_type = 'bfgs';
            options.ipopt.print_level = 1;

            start = [0.9; 0.1];
            [result, ~] = ipopt (start, funcs, options);
            rho    = result(1);
            sigmaT = result(2);

            %calculate divergence, spotsize and correlation at nozzle
            DivergenceAtNozzle  = sigmaT;
            SpotsizeAtNozzle    = sqrt(sigmaNull^2 - 2 * rho * sigmaNull * sigmaT * obj.nozzleToIso + sigmaT^2 * obj.nozzleToIso^2);
            CorrelationAtNozzle = (rho * sigmaNull - sigmaT * obj.nozzleToIso) / SpotsizeAtNozzle;

            %save calcuated beam optics data in mcData
            mcData.ProtonsMU     = 1e2;

            mcData.Weight1       = 1;
            mcData.SpotSize1x    = SpotsizeAtNozzle;
            mcData.Divergence1x  = DivergenceAtNozzle;
            mcData.Correlation1x = CorrelationAtNozzle;
            mcData.SpotSize1y    = SpotsizeAtNozzle;
            mcData.Divergence1y  = DivergenceAtNozzle;
            mcData.Correlation1y = CorrelationAtNozzle;

            mcData.Weight2       = 0;
            mcData.SpotSize2x    = 0;
            mcData.Divergence2x  = 0;
            mcData.Correlation2x = 0;
            mcData.SpotSize2y    = 0;
            mcData.Divergence2y  = 0;
            mcData.Correlation2y = 0;
        end
                          
        function obj = writeToBDLfile(obj,filepath)
            %writeToBDLfile write the base data to file "filepath"
            
            
            %look up focus indices
            focusIndex = obj.selectedFocus(obj.energyIndex);
            
            %save mcData acording to used focus index in dataTable
            selectedData = [];
            for i = 1:numel(focusIndex)
                
                selectedData = [selectedData, obj.mcSquareData(focusIndex(i), i)];
            end
            
            obj.dataTable = struct2table(selectedData);
            
            
            machine = obj.machine;
            
            try
                
                fileID = fopen(filepath,'w');
                
                %Header
                %fprintf(fileID,'--matRad: Beam Model for machine %s (%s)--\n',machine.meta.machine,machine.meta.dataType);
                fprintf(fileID,'--UPenn beam model (double gaussian)--\n');
                fprintf(fileID,'# %s\n',machine.meta.description);
                fprintf(fileID,'# created by %s on %s\n\n',machine.meta.created_by,machine.meta.created_on);
                
                fprintf(fileID,'Nozzle exit to Isocenter distance\n');
                fprintf(fileID,'%.1f\n\n',obj.nozzleToIso);
                
                fprintf(fileID,'SMX to Isocenter distance\n');
                fprintf(fileID,'%.1f\n\n',obj.smx);
                
                fprintf(fileID,'SMY to Isocenter distance\n');
                fprintf(fileID,'%.1f\n\n',obj.smy);
                
                fprintf(fileID,'Beam parameters\n%d energies\n\n',size(obj.dataTable,1));

                fclose(fileID);               
                                        
                writetable(obj.dataTable,[filepath '.tmp'],'Delimiter','\t','FileType','text');
                
                fileID = fopen([filepath '.tmp'],'r');
                tableTxt = fread(fileID);
                fclose(fileID);
                
                fileID = fopen(filepath,'a');
                fwrite(fileID,tableTxt);
                fclose(fileID);
                
                delete([filepath '.tmp']);
                
                obj.bdl_path = filepath;
                
            catch MException
                error(MException.message);
            end
        end
          
        function obj = saveMatradMachine(obj,name)
            %save previously calculated mcSquareData in new baseData file
            %with given name
            
            machine = obj.machine;
            [~ ,energyIndex, ~] = intersect([obj.machine.data(:).energy], [obj.mcSquareData(:).NominalEnergy]);
            
            machineName = [obj.machine.meta.radiationMode, '_', name];
            
            count = 1;
            for i = energyIndex'
               
                machine.data(i).mcSquareData = obj.mcSquareData(:,count);
                
                count = count + 1;
            end
            
            save(strcat('../../', machineName, '.mat'),'machine');
        end
   end
end

