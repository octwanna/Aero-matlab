%% One-dimensional Conservation Law Solver 
% Computing Burgers solution using a DG-FEM routine with Polynomial
% truncation for the nonlinear terms. 
%
% for solving the following problem:
%
% u_t + f(u)_x = s(u)
%
% Based on ideas of the following papers:
%
% 1. TVB Runge-Kutta Local Projection Discontinuous Galerkin Finite Element
% Method for conservation laws II: General Framework. (1989)
% 2. Runge-Kutta Discontinuous Galerkin Method Using WENO Limiters. (2005)
%
% Coded by Manuel Diaz 2012.12.05

%% Clear Work Space 
clear all; close all; %clc;

%% Simulation Parameters
k         = 3;      % Space order / Number of degress of freedom: 0 to k
np        = k+1;    % Number of points per Cell/Element
quadn     = 4;      % element grid: {1}sLeg, {2}Lobatto, {3}Leg, {4}Radau
rks       = 3;      % Time order of the Sheme/RK stages
flux_type = 1;      % {1}Roe, {2}Global LF, {3}LLF
a         = 0.5;    % scalar advection speed
cfl       = 0.3;    % Courant Number
tEnd      = pi/15;  % Final Time for computation
nx        = 10;     % Number of Cells/Elements
MM        = 0.01;   % TVB constant M
IC_case   = 3;      % 4 cases are available
plot_figs = 1;      % {1}Plot figures, {0}Do NOT plot figures

%% Define Grid Cell's (Global) nodes
% Building nodes for cells/elements: 
x_left = 0; x_right = 1; dx = (x_right-x_left)/nx;
x_nodes = x_left : dx : x_right; % cells nodes

%% flux function
%f = @(c,w) c * w;    % for Linear advection
F = @(c,w) w.^2/2;    % for Invicid burger's eq.
% and derivate of the flux function
%df = @(c,w) c*(w/w); % for Linear advection
dF = @(c,w) w;       % for Invicid burger's eq.

%% Source term fucntion
S = @(u) u.^2;       % for Source Term

%% SETUP
% 1. Build Cells/Elements (Local) inner points (quadrature points).
% 2. Build Weigthing values for our local.
% 3. Build Vandermonde Matrix for our local quadrature points.
[x,xi,w,V] = setup(k,x_nodes,quadn);

% Compute Math Objetcs:
if quadn == 1; bmath = 1; else bmath = 2; end;
switch bmath
    case{1} % Build Math objects for scaled Legendre polynomials. See Ref.[1]
        % M matrix
        M = diag([1 1/12 1/180 1/2800 1/44100 1/698544 1/11099088 1/176679360]);        
        % D matrix 
        D = [ ...
            0, 1, 0, (1/10), 0, (1/126), 0, (1/1716); ...
            0, 0, (1/6), 0, (1/70), 0, (1/924), 0; ...
            0, 0, 0, (1/60), 0, (1/756), 0, (1/10296); ...
            0, 0, 0, 0, (1/700), 0, (1/9240), 0; ...
            0, 0, 0, 0, 0, (1/8820), 0, (1/120120); ...
            0, 0, 0, 0, 0, 0, (1/116424), 0; ...
            0, 0, 0, 0, 0, 0, 0, (1/1585584); ...
            0, 0, 0, 0, 0, 0, 0, 0];
        % invM matrix
        invM = inv(M);
        % Scaled Legendre polynomials of deg 'l' evaluated at x = +1/2
        for l = 0:k; % Polynomials degree
        C1 = sLegendreP(l,0.5);
        end
        % Scaled Legendre polynomials of deg 'l' evaluated at x = -1/2
        for l = 0:k; % Polynomials degree
        C1 = sLegendreP(l,-0.5);
        end
        
    case{2} % Build Math objects for non-scaled Legendre polynomials See Ref.[3]
    l = 0:k; % Polynomials degree
    % M matrix
    M = diag((2*+1)/dx);        
    % D matrix 
    D = zeros(np,np);
    for l = 0:k             % For all degress of freedom
        i = l+1;            % Dummy index
        for j=1:np          % For all local points
            if j>i && rem(j-i,2)==1
                D(i,j)=2;   % D or diffentiated Legendre Matrix
            end
        end
    end
    % Scaled Legendre polynomials of degree 'l' evaluated at x = +1
    C1 = (-1)^(l);
    % Scaled Legendre polynomials of degree 'l' evaluated at x = -1
    C2 = (1)^(l);
end

%% Initial Condition, u(x,0) = u0
u0 = u_zero(x,IC_case);
f0 = F(a,u0);
s0 = S(u0);

% Plot IC
%if plot_figs == 1; plot(x,u0); axis([0,2,0,1.2]); end;
if plot_figs == 1; 
    subplot(1,3,1); plot(x,u0); title('u0'); axis tight;
    subplot(1,3,2); plot(x,f0); title('f0'); axis tight;
    subplot(1,3,3); plot(x,s0); title('s0'); axis tight; 
end;


%% Computing the Evolution of the residue 'L', du/dt = L(u) 
% Load Initial conditions
u = u0;
f = f0;
s = s0;

% transform u(x,t) to degress of freedom u(t)_{l,i} for each i-Cell/Element
ut = zeros(np,nx);
for l = 0:k             % for all degress of freedom
    i = l+1;            % Dummy index
    for j = 1:nx
        ut(i,j) = (2*l+1)/2*sum(w(:,j).*u(:,j).*V(:,i));
    end
end
    
% transform f(x,t) to degress of freedom f(t)_{l,i} for each i-Cell/Element
st = zeros(np,nx); 
for l = 0:k             % for all degress of freedom
    i = l+1;            % Dummy index
    for j = 1:nx
        st(i,j) = (2*l+1)/2.*sum(w(:,j).*s(:,j).*V(:,i));
    end
end

% transform s(x,t) to degress of freedom s(t)_{l,i} for each i-Cell/Element
ft = zeros(np,nx);
for l = 0:k             % for all degress of freedom
    i = l+1;            % Dummy index
    for j = 1:nx
        ft(i,j) = (2*l+1)/2.*sum(w(:,j).*f(:,j).*V(:,i));
    end
end

% Set Initial time step
time = 0; % time
n    = 0; % counter
%while time < tEnd
    dt = cfl*dx/max(max(abs(u)));   % dt, time step
    time = time + dt;               % iteration time
    n    = n + 1;                   % update counter

% Volume term
% Cell Integral volume by Gauss-type quadrature.
v_term = zeros(np,nx);
for l = 0:k
    i = l+1;    % Dummy index
    for j = 1:nx
        v_term(i,j) = (2*l+1)/2*sum(w(:,j).*F(a,u0(i,j)).*dsLegendreP(l,xi));
    end
end

% Contribution of fluxes at the cell's boundaries




%end % time loop 

%% Transform degress of freedom u(t)_{l,i} back to space-time values u(x,t)
u = (ut'*V')';
f = F(a,u);
s = S(u);
figure
if plot_figs == 1; 
    subplot(1,3,1); plot(x,u); title('u'); axis auto;
    subplot(1,3,2); plot(x,f); title('f'); axis auto;
    subplot(1,3,3); plot(x,s); title('s'); axis auto; 
end;
