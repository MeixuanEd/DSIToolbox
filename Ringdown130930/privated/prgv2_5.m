% The Prony analysis subroutines solve the following problem:
%
% Consider the following Laplace transform system:
%
%               ----------
%   U(s)  ----->|  G(s)  |----->sampled at T----->
%               ----------  Y(s)
%
% A system model G(s) is identified where
%
%                  n     R(i)
%   G(s) = THRU + sum ---------
%                 i=1  s - p(i)
%
% where the poles (p(i)'s) are assumed distinct and are allowed to
% be zero.  U(s) is a known input of the form
%
%          NINPUTS            exp(-s*DELAY(j-1)) - exp(-s*DELAY(j))
%   U(s) =   sum    INAMP(j) ---------------------------------------
%            j=1                                s
%
% This program uses Prony analysis to fit yhat(t) to the actual system's
% output y(t).  The fit is performed over the interval DELAY(NINPUTS-1)
% to DELAY(NINPUTS) or after DELAY(NINPUTS), depending on the users choice.
%
%   1. Fit y(t)
%   2. Re-order identified terms and reduce model order
%   3. Calculate transfer-function terms
% **************************************************************************
%
% User provided variables
% These are the variables listed in the MATLAB function call above.  They
% are not passed directly to this function.
%
%   sigdat     = Signal data matrix.  Columns contain signals to use in
%                multi-output Prony analysis.
%
%   tstep      = Sample period.
%
%   shftnnft   = [shift; nnfit];
%                shift = Number of points to skip in each column before
%                        performing Prony analysis.
%                nnfit = Number of points from each column to include in
%                        Prony analysis.
%
%   inpulses   = Input pulse matrix.
%                ======= Laurentiu Marinovici ======
%                First column is the delay value and the second coulmn has the amplitude value.
%                ==================================================  
%
%   known_modes        = Known mode matrix.  First column is damping coefficients and
%                second is mode frequencies (in rad/sec).
%
%   xcon       = Control vector.  This is both an input and an output.
%              = [modes lpocon pircon dmodes lpmcon lpacon fbcon ordcon ...
%                trimre ftrimh ftriml];
%                modes  = Number of modes in addition to those entered in
%                         knwmod to calculate.
%                         If modes == 0 just calculate residues for knwmod.
%                         If modes <  0 automatically determine number of
%                                       additional modes to calculate.
%                scalmode = ???????????????????????????????????????????????
%                lpocon = Order of linear prediction.
%                pircon = Rank of pseudo-inverse in linear prediction.
%                dmodes = Number of modes identified in linear prediction.
%                lpmcon = Linear prediction method.
%                lpacon = Linear prediction algorithm.
%                fbcon  = Forward/backward linear prediction.
%                ordcon = Method for mode ordering.
%                trimre = Residue trim level.
%                ftrimh = Upper trim frequency.
%                ftriml = Lower trim frequency.
%
%   identmodel = Array with identified model parameters.
%                Mode number varies along first dimension.
%                Parameter type varies along second dimension.
%                (dampf, frqrps, amp, phase, resr, resi, releng, afpe)
%                Signal number varies along third dimension.
%
%   wrnerr     = Matrix of strings containing warning messages.
%
%   ftlerr     = Error message if fatal error occurs.  Other outputs will
%                contain no data.
%
% **************************************************************************
%
% The following represents the MATLAB translation of the original FORTRAN
% code
% Author of the MATLAB code: Laurentiu Dan Marinovici
% Date: August - September 2013
%
% **************************************************************************
function [identmodel, xcon, plhs_3, plhs_4] =...
    prgv2_5(sigdat, tstep, shftnnft, inpulses, known_modes, xcon),
    
    global ntaille nsize nwork nsigs nflgs inpmax mincon
    % according to DIMPAR.CMN, the following sizes are imposed
    nsize = 128;
    ntaille = 8192; % number of signal samples; would it be possible for each signal to have different number of samples?
    % ntaille = size(xsig, 1);
    nwork = 3 * nsize * ntaille;
    nsigs = 20;
    nflgs = 6; inpmax = 10; mincon = 1e-12;
    
    % create the error messages
    global wrnflg mretr copyrt fatalerr argerr orderr
    [mretr, wrnflg, copyrt, fatalerr, argerr, orderr] = create_dict();
    
    % Calculating the number of known modes
    knwmod = size(known_modes, 1);
    % Number of desired modes = number of additional modes + number of
    % known modes
    qcon = xcon(1) + knwmod;
    % Number of signals
    nsigs_act = size(sigdat, 2);
    
    % ===============================
    % Initialize returned variables
    wrnerr = wrnflg;
    ftlerr = fatalerr;
    plhs_3 = [];
    plhs_4 = [];
    % ================================
    % These are actually internal variables for prspak function
    % BIG BIG EXCLAMATION SIGN !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    % It turns out that initially qcon = -1, which results in empty
    % matrices for the initialization lines below. This caused a
    % "Subscripted assignment dimension mismatch" error later on for resr2.
    % Initializing them based on nsize = 128 like in the FORTRAN code would
    % cause unneccessary zeros later. Conclusion: let's see what happens if
    % we do not initialize resr2, resi2, aic2, and releng2.
    dampf1 = zeros(nsize, 1);
    frqrps1 = zeros(nsize, 1);
    phase1 = zeros(nsize, 1);
    ampopt1 = zeros(nsize, 1);
    resr1 = zeros(nsize, 1);
    resi1 = zeros(nsize, 1);
    aic1 = zeros(nsize, 1);
    releng1 = zeros(nsize, 1);
    % =================================
    dampf2 = zeros(nsize, nsigs_act);
    frqrps2 = zeros(nsize, nsigs_act);
    phase2 = zeros(nsize, nsigs_act);
    ampopt2 = zeros(nsize, nsigs_act);
    % resr2 = zeros(nsize, nsigs_act);
    % resi2 = zeros(nsize, nsigs_act);
    % aic2 = zeros(nsize, nsigs_act);
    % releng2 = zeros(nsize, nsigs_act);
    % =================================
    % These are the returned variables
    identmodel = zeros(nsize, 8*nsigs_act);
    % =================================
    
    % Initialize constants
    lg = -log(1e+8);
    
    % initialize the signal data matrix that is going to be used by PRSPAK
    % According to the FORTRAN code, XSIG could end up to have uneven
    % columns, if NNFIT is different for different signal columns in
    % SIGDAT; therefore, let's initialize XSIG with zeros for the time
    % being
    xsig = zeros(ntaille, nsigs_act);
    
    % Check the required number of input and output arguments
    if nargin ~= 6,
        error(argerr.err_msg{1});
    end
    if nargout ~= 4,
        error(argerr.err_msg{2});
    end
    
    % Check validity of the input arguments
    if ~isreal(sigdat),
        error(argerr.err_msg{3});
    end
    % Check dimensions of first input argument
    % do we really need these in MATLAB
    if size(sigdat, 1) > ntaille | size(sigdat, 2) < 1 | size(sigdat, 2) > nsigs,
        error(argerr.err_msg{5});
    end
    % Check dimension of the second input argument
    % if at least one dimension mismatches, then throw error
    if any(size(tstep) ~= [1, 1]),
        error(argerr.err_msg{6});
    end
    % Check dimension of the third input argument
    % if at least one dimension mismatches, then throw error
    if any(size(shftnnft) ~= [2, size(sigdat, 2)]),
        error(argerr.err_msg{7});
    end
    % Check dismension of the fourth(inpulses) argument
    if size(inpulses, 1) > 0 & (size(inpulses, 1) > inpmax | size(inpulses, 2) ~= 2),
        error(argerr.err_msg{8});
    end
    % Check dimension of the fifth argument
    if knwmod > 0 & (knwmod > nsize | size(known_modes, 2) ~= 2),
        error(argerr.err_msg{9});
    end
    % Check dimension of the sixth element
    % if at least one dimension mismatches, then throw error
    if all(size(xcon) > [1, 1]) | all(size(xcon) ~= [12, 12]),
        error(argerr.err_msg{10});
    end
    % Initialize and check shift and nnfit
    shift = shftnnft(1, :);
    nnfit = shftnnft(2, :);
    shift(shift < 0) = 0; % zerorize all negative shift values
    nnfit(nnfit < 0) = size(sigdat, 1); % zerorize all negative number of fitting elements
    if any(nnfit < 3) | any(shift + nnfit > size(sigdat, 1)),
        error(argerr.err_msg{11});
        % plhs_4 = ftlerr.err_msg(ftlerr.num_key == 0);
    end
    % Read the elements out of the control vector
    if qcon > nsize,
        error(argerr.err_msg{12});
    end
    % setting up the control variable for the type of calculation to
    % perform
    if knwmod > 0,
        if knwmod > qcon,
            knwcon = 2;
        else,
            knwcon = 1; % the number of desired modes is the same with the number of known modes; there are no other modes required
        end
    else
        knwcon = 0; % full calculation is performed
    end
    scalmod = xcon(2);
    lpocon = xcon(3);
    pircon = xcon(4);
    lpmcon = xcon(6);
    lpacon = xcon(7);
    fbcon = xcon(8);
    ordcon = xcon(9);
    trimre = xcon(10);
    ftrimh = xcon(11);
    ftriml = xcon(12);
    
    % Create the signal data matrix for prspak. Normalize if requested.
    for sig_ind = 1:size(sigdat, 2),
        xsig(1:nnfit(sig_ind), sig_ind) = sigdat((shift(sig_ind) + 1):(nnfit(sig_ind) + shift(sig_ind)), sig_ind);
        % if scaling need be done
        if scalmod ~= 0,
            sc = max(abs(xsig(:, sig_ind))); % maximum absolute value of the signal used as scaling factor
            if sc > 0, % scale if scaling factor greater than 0
                xsig(:, sig_ind) = xsig(:, sig_ind)/sc;
            end
            scfac(sig_ind) = sc;
        end
    end
    
    % Copy data out of MATLAB arrays
    ninputs = size(inpulses, 1); % number of inputs = number of inpulses
    if ninputs ~= 0,
        delay = inpulses(:, 1);
        inamp = inpulses(:, 2);
    end
    
    if knwmod > 0,
        dampf1 = known_modes(:, 1);
        frqrps1 = known_modes(:, 2);
    end
    
    % Call PRSPAK to perform PRONY analysis
    [dampf1, frqrps1, ampopt2, phase2, dmodes, wrnflg_vect, mretr_key,...
        lpocon, lpmcon, lpacon, fbcon, pircon, knwcon, knwmod, qcon, trimre, ftrimh, ftriml] =... 
        prspak(xsig, size(xsig, 2), tstep, nnfit, lpocon, lpmcon, lpacon, fbcon, pircon,...
        knwcon, knwmod, qcon, trimre, ftrimh, ftriml, dampf1, frqrps1);
    
    % if PRSPAK is successful
    if mretr_key == 0,
        % Loop to copy mode dampings and frequencies. Scale residues.
        dampf2 = repmat(dampf1, 1, size(sigdat, 2));
        frqrps2 = repmat(frqrps1, 1, size(sigdat, 2));
        if scalmod ~= 0,
            ampopt2 = ampopt2.*repmat(scfac, size(ampopt2, 1), 1);
        end
        
        % Reorder modes and calculate transfer function residues.
        for ind = 1:size(sigdat, 2),
            workrv1 = (shift(ind) + [0:(nnfit(ind) - 1)])'*tstep;
            dampf1 = dampf2(:, ind);
            frqrps1 = frqrps2(:, ind);
            ampopt1 = ampopt2(:, ind);
            phase1 = phase2(:, ind);
            
            stable = lg/(tstep * (nnfit(ind) - 1));
            dammax = -1; % set negative to disable
            frqmax = -1; % set negative to disable
            alpha = 1;
            beta = 0;
            [ampopt1, dampf1, frqrps1, phase1, aic1, releng1, mretr2] = reorder_modes(workrv1, nnfit(ind),...
                qcon, ampopt1, dampf1, frqrps1, phase1, dammax, frqmax, stable, alpha, beta, ordcon);
            
            if ninputs > 0,
                [resr1, resi1, dcterm] = tranfun(ninputs, delay, inamp, tstep, qcon, dampf1, frqrps1, ampopt1,...
                    phase1, shift(ind));
            end
            
            t = shift(ind) * tstep;
            ampopt1 = ampopt1 .* exp(t * dampf1);
            phase1 = phase1 - t * frqrps1;
            phase1(abs(phase1) > pi) = rem(phase1(abs(phase1) > pi), 2*pi);
            
            if ninputs == 0,
                resr1 = ampopt1 .* cos(phase1) / 2;
                resi1 = ampopt1 .* sin(phase1) / 2;
            end
            
            % Since, technically, we reordered the ampopt1, frqrps1, etc.
            % vectors in reorder_modes function, there's a need to
            % reconstruct the following.
            dampf2(:, ind) = dampf1;
            frqrps2(:, ind) = frqrps1;
            ampopt2(:, ind) = ampopt1;
            phase2(:, ind) = phase1;
            resr2(:, ind) = resr1;
            resi2(:, ind) = resi1;
            aic2(:, ind) = aic1;
            releng2(:, ind) = releng1;
        end
    end
    
    % Create the output arguments
    if (mretr_key ~= 0) | (mretr2 ~= 0),
        mret = 1;
    else,
        mret = 0;
    end
    
    if mret == 0,
        identmodel_temp = [dampf2; frqrps2; ampopt2; phase2;...
            resr2; resi2; releng2; aic2];
        identmodel = reshape(identmodel_temp, qcon, nsigs_act*8);
        xcon = [qcon; scalmod; lpocon; pircon; dmodes; lpmcon; lpacon; fbcon; ordcon; trimre; ftrimh; ftriml];
        
        m = sum(wrnflg_vect ~= 0);
        wrn_messages = wrnflg.err_msg(wrnflg_vect ~= 0);
        
        if m == 0,
            plhs_3 = [];
        elseif m == 1,
            plhs_3 = wrn_messages(m);
        else,
            plhs_3 = wrn_messages;
        end
        plhs_4 = [];
    else,
        plhs_3 = 0;
        if mretr_key == 0,
            if mretr2 == 12,
                plhs_4 = ftlerr.err_msg(ftlerr.num_key == 6);
            elseif mretr2 == 101,
                plhs_4 = ftlerr.err_msg(ftlerr.num_key == 7);
            else,
                plhs_4 = ftlerr.err_msg(ftlerr.num_key == 8);
            end
        else,
            if mretr_key == 100,
                plhs_4 = ftlerr.err_msg(ftlerr.num_key == 1);
            elseif (mretr_key == 102) | (mretr_key == 103),
                plhs_4 = ftlerr.err_msg(ftlerr.num_key == 2);
            elseif mretr_key == 104,
                plhs_4 = ftlerr.err_msg(ftlerr.num_key == 3);
            elseif mretr_key == 105,
                plhs_4 = ftlerr.err_msg(ftlerr.num_key == 4);
            elseif mretr_key == 110,
                plhs_4 = ftlerr.err_msg(ftlerr.num_key == 5);
            else,
                plhs_4 = ftlerr.err_msg(ftlerr.num_key == 7);
            end
    end
end