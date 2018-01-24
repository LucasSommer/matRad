classdef matRad_MeanDose < DoseObjectives.matRad_DoseObjective
    %MATRAD_MEANDOSE Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (Constant)
        name = 'Min. Mean Dose';
        parameterNames = {'d^{ref}'};
        parameterIsDose = true;
        %parameterNames = {};
        %parameterIsDose = [];
    end
    
    properties
        parameters = {0};        
        penalty = 1;
    end
    
    methods 
        %% Calculates the Objective Function value
        function fDose = computeDoseObjectiveFunction(obj,dose)
            %fDose = obj.penalty * abs(mean(dose(:)) - obj.parameters{1});
            fDose = obj.penalty * (mean(dose(:)) - obj.parameters{1})^2;
        end
        
        %% Calculates the Objective Function gradient
        function fDoseGrad   = computeDoseObjectiveGradient(obj,dose)
            %fDoseGrad = (obj.penalty/numel(dose))*sign(dose(:)-obj.parameters{1});
            fDoseGrad = obj.penalty*2*(mean(dose(:))-obj.parameters{1}) * ones(size(dose(:)))/numel(dose);
        end
    end
    
end

