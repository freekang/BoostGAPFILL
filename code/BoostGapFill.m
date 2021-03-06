function [newReactions,RxnsRecovered,newMetabolites,newModel]=BoostGapFill(Model,Rxns2Remove,noOfRxns2Add,blacklist,options)
global integerSoln solver modeFlag tempModel biomass_threshold def_weight maxTime maxIter penID testFlag newMet newMetPenalty

% main BoostGapFill function
%input
% model:          COBRA model
% Rxns2Remove:    reactions to be deleted
% noOfRxns2Add:   number of reactions to  be added
% blacklist:      list of blacklisted reactions

%options structure
% mFlag:                boolean indicating if a new model with the predicted reactions is to be returned
% maxIter:              maximum number of iterations
% solver:               solver to be used% the following solvers can be used: 'ibm_cplex','gurobi' and MATLAB's 'lsqlin'.
% mode:                 different modes of running BoostGAPFILL ('pattern','pattern-constraints','integrated')
% newMet:               flag to determine whether or not to include reactions with new metabolites
% integerSoln:          flag to determine whether to solve the orignal integer
%                       least squares problem or the relaxed version
% numSolns:             number of solution sets required
% biomass_threshold:    threshold for viable biomass growth
% maxTime:              used to limit the time for each iteration of the optimization problem in BoostGapFill.
%                       important to set when running in integrated mode and when integer solutions are required
% def_weight:          used when integrating with FASTGAPFILL
% rxnThreshold:         value between 0 and 1 ; used in BoostGAPFILL to alter the number of reactions selected;
%                       lower values in larger number of reactions selected.
% newMetPenalty:        newMetPenalty paramter that penalizes the addition of new metabolites.
%                       higher numbers mean fewer selected reactions with new metabolites


%output
% newReactions : new reaction predictions
% RxnsRecovered: reactions that match deleted reactions
% tempModel:     new model created after adding predicted reactions

% Authors: Tolutola Oyetunde and Muhan Zhang,  Washington University in St. Louis


% setting default options
if isempty(options)
    options.mFlag=1;
    options.maxIter=10;
    options.solver='ibm_cplex';
    options.mode='pattern';
    options.newMet=false;
    options.integerSoln=false;
    options.numSolns=1;
    options.biomass_threshold=0.05;
    options.maxTime=1;
    options.def_weight=10;
    options.rxnThreshold=1e-12;
    options.newMetPenalty=20;
    
else
    if ~isfield(options,'mFlag')
        options.mFlag=1;
    end
    if ~isfield(options,'maxIter')
        options.maxIter=10;
    end
    if ~isfield(options,'solver')
        options.solver='ibm_cplex';
    end
    if ~isfield(options,'mode')
        options.mode='pattern';
    end
    if ~isfield(options,'newMet')
        options.newMet=false;
    end
    if ~isfield(options,'integerSoln')
        options.integerSoln=false;
    end
     if ~isfield(options,'numSolns')
        options.numSolns=1;
    end
    
    if ~isfield(options,'biomass_threshold')
        options.biomass_threshold=0.05;
    end
    if ~isfield(options,'maxTime')
        options.maxTime=1;
    end
    
    if ~isfield(options,'def_weight')
        options.def_weight=10;
    end
    if ~isfield(options,'rxnThreshold')
        options.rxnThreshold=1e-12;
    end
    if ~isfield(options,'newMetPenalty')
        options.newMetPenalty=20;
    end
    
    
    
end

% make global parameters available
integerSoln=options.integerSoln;
solver=options.solver;
modeFlag=options.mode;
biomass_threshold=options.biomass_threshold;
def_weight=options.def_weight;
maxTime=options.maxTime;
maxIter=options.maxIter;
newMet=options.newMet;
newMetPenalty=options.newMetPenalty;
% testFlag: 1 if the function is called by testgapfill in which case the
% full stoichiometric matrix is used else the 'partially' full
% stoichiometric matrix is used (called by BoostGapFill)
testFlag=0;

% preprocess data
if ~isempty(Rxns2Remove)
    tempModel=removeRxns(Model,Rxns2Remove,[],false);
else
    tempModel=Model;
end
S = Model.S;    %stoichiometric matrix S
S = full(spones(S));   %make to binary
R = Model.rxns;   %reactions R
M=Model.mets;

if newMet
    sUS = Model.universalStoich;
    US = full(spones(sUS)); %US with logical values
    unrnames = Model.universalRxns;
    %     sUS=Model.universalStoich;
    %     US=full(spones(sUS));
    %
    %     unrnames=Model.universalRxns';
    %
    %     % partial universal stoichiometric matrix
    %     US(~ismember(Model.universalMets,Model.mets),:)=[];
    %     sUS(~ismember(Model.universalMets,Model.mets),:)=[];
    
    %     S = Model.universalStoich;    %stoichiometric matrix S
    %     S = full(spones(S));   %make to binary
    %     R = Model.universalRxns;   %reactions R
    %     M=Model.universalMets;
    
else
    
    %     US = full(spones(Model.US)); %US with logical values
    %     sUS = Model.US;
    %     unrnames = Model.unrnames;
    
    sUS=Model.universalStoichSmall;
    US=full(spones(sUS));
    unrnames=Model.universalRxnsSmall;
    
    %     US = full(spones(Model.US)); %US with logical values
    %     sUS = Model.US;   %US with stoichiometry values    unrnames = Model.unrnames;
    %     unrnames = Model.unrnames;
    
end

% Testnumber = length(Rxns2Remove);
% num_test = length(Testnumber);
% RxnsRecovered = zeros(num_test,1);

threshold=noOfRxns2Add;

% trainnames=tempModel.rxns;
% trainr = sparse(S(:,ismember(R,trainnames)));    %train reactions

trainnames=tempModel.rxns;
trainr = sparse(S(:,ismember(R,trainnames)));    %train reactions



tmp = strcmp(repmat(trainnames,1,size(unrnames,2)),repmat(unrnames,size(trainnames,1),1));  %compare train with unr, save to a matrix
check_repeat = find(sum(tmp)==0);     %keep those unr which never appears in the train reactions
unrepeat_US = US(:,check_repeat);     %the unrepeated US, which excludes the train reactions
unrepeat_unrnames = unrnames(1,check_repeat);


% to be used in the 'integrated' mode of BoostGapFill
tempModel.unrepeat_US=unrepeat_US;
tempModel.trainr=trainr;
tempModel.check_repeat=check_repeat;
tempModel.rlb=Model.lb(ismember(R,trainnames));
tempModel.rub=Model.ub(ismember(R,trainnames));

if options.newMet
    %find reactions to penalize during selection from universal database
    % reactions with metabolites not originally present in the network
    penID=~ismember(unrepeat_unrnames,Model.universalRxnsSmall);
end


%black list
if isempty(blacklist)
    [~,cc] = size(unrepeat_US);
    blacklist = zeros(cc,1);
end

% alternative solutions
newReactions=cell(options.numSolns,1);
RxnsRecovered=cell(options.numSolns,1);
newMetabolites=cell(options.numSolns,1);
newModel=cell(options.numSolns,1);

for j=1: options.numSolns
    [Lambda,scores] = HLpredict(trainr,unrepeat_US,threshold,options.maxIter,blacklist,options.solver);
    % end
    
    switch options.mode
        case {'pattern', 'integrated'}
            %differences between 'pattern' and 'integrated' cases is found in
            %the formulation of the relaxed integer least squares problem
            
            newReactions{j} = unrepeat_unrnames(Lambda');
            
            if ~isempty(Rxns2Remove)
                match = strcmp(repmat(Rxns2Remove,1,size(newReactions{j},2)),repmat(newReactions{j},size(Rxns2Remove,1),1));
                RxnsRecovered{j}= nnz(match);
            else
                RxnsRecovered{j}=[];
            end
            
            if options.newMet
                %find the new metabolites added
                newMetabolites{j}= newMetFind(newReactions{j},M,unrnames);
            else
                newMetabolites{j}=[];
            end
            
            if options.mFlag % if new extendedModel is required
                
                % create new Model with added reactions
                newModel{j}=tempModel;
                sUS = sUS(:,check_repeat);
                dS=sUS(:,logical(Lambda'));
                
                for nrxns=1:noOfRxns2Add
                    rxnName=newReactions{j}{nrxns};
                    rxnID=find(strcmp(Model.unrnames_full,rxnName));
                    metList=Model.unMets{rxnID};
                    stoichVec=Model.unStoich{rxnID};
                    newModel{j} = addReaction(newModel{j},rxnName,metList,stoichVec);
                    
                    %                 cVector=dS(:,nrxns);
                    %                 cLogic=cVector~=0;
                    %                 newModel = addReaction(newModel,newReactions{nrxns},Model.mets(cLogic),cVector(cLogic));
                end
                
            end
            
        case 'pattern-constraints'
            % in this mode, the pattern-based module is used as a preprocessing
            % step for FASTGAPFILL
            
            %         WeightsPerRxn.var=10*ones(length(scores),1);
            %         WeightsPerRxn.var(Lambda')=0.5;
            %         %         WeightsPerRxn.var(scores>=0.01)=0;
            WeightsPerRxn.rxns=unrepeat_unrnames';
            
            %best so far
            %         WeightsPerRxn.var=100*ones(length(scores),1);
            %         WeightsPerRxn.var(scores>=0.001)=0;
            %
            
            WeightsPerRxn.var=def_weight*ones(length(scores),1);
            %         WeightsPerRxn.var(scores>=0)=0.0000000001; %(one less for repeat2)
            WeightsPerRxn.var(scores>=options.rxnThreshold)=1e-15; %testing
            %         newResultsArepeat stores with weight=0;
            
            if options.mFlag % if new extendedModel is required
                [newReactions{j},RxnsRecovered{j},~,newModel{j}]=FastGapFillSub(Model,Rxns2Remove,WeightsPerRxn,options.newMet);
            else
                [newReactions{j},RxnsRecovered{j}]=FastGapFillSub(Model,Rxns2Remove,WeightsPerRxn,options.newMet);
            end
            
            if options.newMet
                newMetabolites{j}= newMetFind(newReactions{j},M,unrnames);
            else
                newMetabolites{j}=[];
            end
            
    end
end


