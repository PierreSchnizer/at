function rcor = atsetcorrectiontable(ring,cortab)
%ATSETCORRECTIONTABLE sets a correction table in an AT lattice 
%
% input
% ring: lattice with errors without correction
% cortab: table of integrated correction strenghts
% 
% output
% rcor : lattice with correctors set as specified in cortab
% 
%see also:


% create correctors table
allind = 1:length(ring);

Lengths = atgetfieldvalues(ring,allind,'Length');

% values for lattice with errors no correction
ch0  = atgetfieldvalues(ring,allind,'PolynomB',{1,1});
cv0  = atgetfieldvalues(ring,allind,'PolynomB',{1,1});
cq0  = atgetfieldvalues(ring,allind,'PolynomB',{1,2});
csk0 = atgetfieldvalues(ring,allind,'PolynomA',{1,2});
cs0  = atgetfieldvalues(ring,allind,'PolynomB',{1,3});
co0  = atgetfieldvalues(ring,allind,'PolynomB',{1,4});

% values for lattice with errors and correction
rcor = ring;
rcor  = atsetfieldvalues(rcor,allind,'PolynomB',{1,1},ch0  + cortab.KL0n./Lengths);
rcor  = atsetfieldvalues(rcor,allind,'PolynomB',{1,1},cv0  + cortab.KL0s./Lengths);
rcor  = atsetfieldvalues(rcor,allind,'PolynomB',{1,2},cq0  + cortab.KL1n./Lengths);
rcor  = atsetfieldvalues(rcor,allind,'PolynomA',{1,2},csk0 + cortab.KL1s./Lengths);
rcor  = atsetfieldvalues(rcor,allind,'PolynomB',{1,3},cs0  + cortab.KL2n./Lengths);
rcor  = atsetfieldvalues(rcor,allind,'PolynomB',{1,4},co0  + cortab.KL3n./Lengths);

end