clear 
load data/iAF1260b.mat
load data/unrmet

unMets=cell(length(unrmet),1);
unStoich=cell(length(unrmet),1);
BigMets=[];
for i = 1:length(unrmet)
    cr = unrmet{i};     %current reaction
    cmet = cr.metabolites;           %current metabolites
    for j = 1:length(cmet)    %for each metabolite of the reaction, compare with M and keep the matches and form dS
        cname = strcat(cmet{j}.bigg_id,'_',cmet{j}.compartment_bigg_id);     %unify the format
        unMets{i}=[unMets{i};{cname}];
        BigMets=[BigMets;{cname}];
        unStoich{i}=[unStoich{i};cmet{j}.stoichiometry];
    end
   
    num_met_ur = [num_met_ur,length(cmet)];    %record the number of metabolites for each reaction in unr
   
end

BigMets=unique(BigMets);

for i = 1:length(unrmet)
    i;
    cr = unrmet{i};     %current reaction
    cmet = cr.metabolites;           %current metabolites
    dS = zeros(size(BigMets));
    for j = 1:length(cmet)    %for each metabolite of the reaction, compare with M and keep the matches and form dS
        cname = strcat(cmet{j}.bigg_id,'_',cmet{j}.compartment_bigg_id);     %unify the format
        dS = dS + strcmp(BigMets,cname)*(cmet{j}.stoichiometry);
    end
    num_met_ur = [num_met_ur,length(cmet)];    %record the number of metabolites for each reaction in unr
    US(:,i) = dS;    %append dS to US
end
Model.universalStoich_full = US;
Model.universalMets=BigMets;