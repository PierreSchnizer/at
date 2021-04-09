function [newring,newringrad] = atfastring(ring0,varargin)
%ATFASTRING Generate simplified AT structures
%
% The given ring structure is modified so that cavities are moved to the
% beginning and the rest of the ring is replaced by a linear 6x6 transfer
% matrix followed by a non-linear element providing tune shifts with
% amplitude and momentum.
%
%   [FASTRING,FASTRINGRAD]=ATFASTRING(RING)
%
%RING:          original AT structure. I f radiation is OFF, it will be
%               turned on woth default options.
%
%FASTRING:      Structure containing inactive cavities moved to the
%               beginning, a linear 6x6 matrix and a non-linear element
%               simulating linear chromaticities and tune shift with
%               amplitudes
%
%FASTRINGRAD:   Structure containing unchanged cavities moved to the
%               beginning, a linear 6x6 transfer matrix, a diffusion element
%               and a non-linear element simulating linear chromaticities
%               and tune shift with amplitudes
%
%   [FASTRING,FASTRINGRAD]=ATFASTRING(RING,REFPTS)
%
% The ring is split at the specified locations, and each section is
% transformed in the same way as previously described
%
%[FASTRING,FASTRINGRAD]=ATFASTRING(RING,'Plot') plots the tune shifts with amplitude

global GLOBVAL

[doplot,varargs]=getflag(varargin,'Plot');
split=getargs(varargs,{[]});

% Turn radiation on if necessary
[~,ring0] = check_radiation(ring0, true, 'force');

% Replace thick cavities by [drift, thin cavity, drift]
ring_temp = ring0;
I_cav = findcells(ring0,'Frequency');
for i = length(I_cav):-1:1
    CavElement = ring_temp{I_cav(i)};
    if CavElement.Length ~= 0
        ring_temp{I_cav(i)} = atdrift('CavDrift',CavElement.Length);
        CavElement.Length = 0;
        ring_temp = atinsertelems(ring_temp,I_cav(i),0.5,CavElement);
    end
end
ring0 = ring_temp;

% Define the slices
if islogical(split)
    iend=[find(split) length(ring0)+1];
else
    iend=[split length(ring0)+1];
end
ibeg=[1 iend(1:end-1)];

GLOBVAL.E0=atenergy(ring0);

% Split the ring
ringv=arrayfun(@rearrange,ibeg,iend,'UniformOutput',false);
ringrad=cat(1,ringv{:});
ring=atradoff(ringrad);

[lindata,tunes,xsi]=atlinopt(ring, 0); %#ok<ASGLU>
gamma=(1+lindata.alpha.*lindata.alpha)./lindata.beta;

% Compute closed orbits at the ends of slices
markers=atgetcells(ring,'FamName','xbeg|xend');
orbit4=zeros(6,sum(markers));
orbit4(1:5,:)=findsyncorbit(ring,0,markers);
orbit4=num2cell(orbit4,1);
orbit6=num2cell(findorbit6(ringrad,markers),1);

% Compute the detuning with amplitude
xm=0.001;
zm=0.0005;
r1=detuning(ring,gamma,xm,zm,orbit4(:,1));

counter=0;
[rv,rvrad]=cellfun(@rebuild,ringv,orbit4(1:2:end),orbit6(1:2:end),...
    orbit4(2:2:end),orbit6(2:2:end),'UniformOutput',false);

nonlin_elem=atbaselem('NonLinear','DeltaQPass',...
    'Betax',lindata.beta(1),'Betay',lindata.beta(2),...
    'Alphax',lindata.alpha(1),'Alphay',lindata.alpha(2),...
    'Qpx',xsi(1),'Qpy',xsi(2),...
    'A1',r1(1),'A2',r1(2),'A3',r1(4),...
    'T1',-orbit4{end},'T2',orbit4{end});

nonlin_elemrad=atbaselem('NonLinear','DeltaQPass',...
    'Betax',lindata.beta(1),'Betay',lindata.beta(2),...
    'Alphax',lindata.alpha(1),'Alphay',lindata.alpha(2),...
    'Qpx',xsi(1),'Qpy',xsi(2),...
    'A1',r1(1),'A2',r1(2),'A3',r1(4),...
    'T1',-orbit6{end},'T2',orbit6{end});

newring=cat(1,rv{:},nonlin_elem);
newringrad=cat(1,rvrad{:},nonlin_elemrad);

    function rg=rearrange(i1,i2)
        % return the ring slice form i1 to i2
        slice=ring0(i1:i2-1);
        cav=atgetcells(slice,'Frequency') | atgetcells(slice,'Class','RingParam');
        rg=[slice(cav);atmarker('xbeg');slice(~cav);atmarker('xend')];
    end

    function [rg,rgrad]=rebuild(slicerad,o4b,o6b,o4e,o6e)
        % Computes linear element and diffusion element for the slice
        counter=counter+1;
        cc=num2str(counter);
        slice = atradoff(slicerad);
%       m1=atmarker(['xbeg' cc]);
%       m2=atmarker(['xend' cc]);
        i1=find(atgetcells(slice,'FamName','xbeg'),1);
        dipoles=atgetcells(slice,'BendingAngle');
        theta=atgetfieldvalues(slice(dipoles),'BendingAngle');
        lendp=atgetfieldvalues(slice(dipoles),'Length');
        s=findspos(slice, length(slice)+1);
        I2=sum(abs(theta.*theta./lendp));
        
        m66norad=symplectify(findm66(slice(i1:end), 'orbit', o4b));
        lin_elem=atM66(['Linear_' cc],m66norad,'T1',-o4b,'T2',o4e,'Length',s,'I2',I2);
        rg=[slice(1:i1-1);lin_elem];
        
        m66rad=findm66(slicerad(i1:end), 'orbit', o6b);
        lin_elemrad=atM66(['Linear_' cc],m66rad,'T1',-o6b,'T2',o6e,'Length',s,'I2',I2);
        %diff_elem=atQuantDiff(['Diffusion_' cc],quantumDiff(slicerad,'orbit',o6b));
        diff_elem=atQuantDiff(['Diffusion_' cc], slicerad, 'orbit0', o6b);
        rgrad=[slicerad(1:i1-1);lin_elemrad;diff_elem];
    end

    function r=detuning(ring,gamma,xm,zm,orbit)
        x2=linspace(0,xm.*xm,10);
        z2=linspace(0,zm.*zm,10);
        [nuxx,nuzx]=atnuampl(ring,sqrt(x2),1,orbit);
        [nuxz,nuzz]=atnuampl(ring,sqrt(z2),3,orbit);
        if doplot
            tune0=floor([nuxx(1);nuzz(1)]);
            subplot(2,1,1);
            plot(x2,[nuxx;nuzx]-tune0(:,ones(1,10)));
            subplot(2,1,2);
            plot(z2,[nuxz;nuzz]-tune0(:,ones(1,10)));
        end
        rx=([nuxx-nuxx(1);nuzx-nuzx(1)]*x2')./(x2([1 1],:)*x2')/gamma(1);
        rz=([nuxz-nuxz(1);nuzz-nuzz(1)]*z2')./(z2([1 1],:)*z2')/gamma(2);
        r=2*[rx;rz];
    end
end
