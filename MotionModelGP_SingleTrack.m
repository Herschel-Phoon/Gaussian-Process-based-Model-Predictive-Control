%------------------------------------------------------------------
% Programed by: 
%   - Lucas Rath (lucasrm25@gmail.com)
%   - 
%   -
%------------------------------------------------------------------

classdef MotionModelGP_SingleTrack < MotionModelGP
%--------------------------------------------------------------------------
%   xk+1 = fd(xk,uk) + Bd * ( d(zk) + w ),    
%
%       where: zk = Bz*xk,
%              d ~ N(mean_d(zk),var_d(zk))
%              w ~ N(0,sigmaw)
%
%   
%   x = [...]'   
%   u = [...]'               
%   
%--------------------------------------------------------------------------
 
    properties
        cf  = 100  % front coornering stiffness
        cr  = 100  % rear coornering stiffness
        M   = 1239 % vehicle mass
        Iz  = 1752 % vehicle moment of inertia (yaw axis)
        g   = 9.81 % gravitation
        l_f  = 1.19016 % distance of the front wheel to the center of mass 
        l_r  = 1.37484 % distance of the rear wheel to the center of mass
        i_g = [3.91 2.002 1.33 1 0.805] % transmissions of the 1st ... 5th gear
        i_0 = 3.91; % motor transmission
        R = 0.302; % wheel radius
    end
    
    properties(SetAccess=private)
        Bd = [0 0 1 0 0 0 0 0 0 0]';       % xk+1 = fd(xk,uk) + Bd*d(zk)
        Bz = eye(10)        % z = Bz*x     
        n = 10              % number of outputs x(t)
        m = 5               % number of inputs u(t)
    end
    
    methods
        function obj = MotionModelGP_SingleTrack(d,sigmaw)
        %------------------------------------------------------------------
        %   object constructor
        %------------------------------------------------------------------
            % call superclass constructor
            obj = obj@MotionModelGP(d,sigmaw);
        end
        
        function [xdot, grad_xdot] = f (obj, x, u)
        %------------------------------------------------------------------
        %   Continuous time dynamics of the single track (including
        %   disturbance):
        %------------------------------------------------------------------
            
            sx = x(1);
            sy = x(2);
            v = x(3);
            beta = x(4);
            psi = x(5);
            omega = x(6);
            x_dot = x(7);
            y_dot = x(8);
            psi_dot = x(9);
            varphi_dot = x(10);
            
            delta = u(1);  % steering angle
            G     = 1; %u(2);  % gear
            F_b    = u(3);  % brake force
            zeta  = u(4);  % brake force distribution
            phi   = u(5);  % acc pedal position
            
             %wheel slip
            if v<=obj.R*varphi_dot % traction slip? (else: braking slip)
                S=1-(v/(obj.R*varphi_dot)); %traction wheel slip
            else
                S=1-((obj.R*varphi_dot)/v); % braking slip
            end
            if isnan(S) % wheel slip well-defined?
                S=0; % recover wheel slip
            end
%             S=0; % neglect wheel slip
            
            n=v*obj.i_g(G)*obj.i_0*(1/(1-S))/obj.R; % motor rotary frequency
            
            if isnan(n) % rotary frequency well defined?
                n=0; %recover rotary frequency
            end
            if n>(4800*pi)/30 % maximal rotary frequency exceeded?
                n=(4800*pi)/30; % recover maximal rotary frequency
            end
            
            T_M=200*phi*(15-14*phi)-200*phi*(15-14*phi)*(((n*(30/pi))^(5*phi))/(4800^(5*phi))); % motor torque
            
            %slip angles and steering
            a_f=delta-atan((obj.l_f*psi_dot-v*sin(beta))/(v*cos(beta))); % front slip angle
            a_r=atan((obj.l_r*psi_dot+v*sin(beta))/(v*cos(beta))); %rear slip angle
            
            if isnan(a_f) % front slip angle well-defined?
                a_f=0; % recover front slip angle
            end
            if isnan(a_r) % rear slip angle well-defined
                a_r=0; % recover rear slip angle
            end

            F_x_r = T_M - F_b;  % longitudinal force rear wheel
            F_x_f = 0;          % longitudinal force front wheel
            F_y_r = obj.cr * a_r;   % rear lateral force
            F_y_f = obj.cf * a_f;   % front lateral force

            % vector field (right-hand side of differential equation)
            
            x_dot = v*cos(psi-beta); % longitudinal velocity
            y_dot = v*sin(psi-beta); % lateral velocity
            v_dot = (F_x_r*cos(beta)+F_x_f*cos(delta+beta)-F_y_r*sin(beta) -F_y_f*sin(delta+beta))/obj.M; % acceleration
            beta_dot = omega-(F_x_r*sin(beta)+F_x_f*sin(delta+beta)+F_y_r*cos(beta) +F_y_f*cos(delta+beta))/(obj.M*v); % side slip rate
            psi_dot  = omega; % yaw rate
            omega_dot=(F_y_f*obj.l_f*cos(delta)-F_y_r*obj.l_r +F_x_f*obj.l_f*sin(delta))/obj.Iz; % yaw angular acceleration
            x_dot_dot=(F_x_r*cos(psi)+F_x_f*cos(delta+psi)-F_y_f*sin(delta+psi) -F_y_r*sin(psi))/obj.M; % longitudinal acceleration
            y_dot_dot=(F_x_r*sin(psi)+F_x_f*sin(delta+psi)+F_y_f*cos(delta+psi) +F_y_r*cos(psi))/obj.M; % lateral acceleration
            psi_dot_dot=(F_y_f*obj.l_f*cos(delta)-F_y_r*obj.l_r  +F_x_f*obj.l_f*sin(delta))/obj.Iz; % yaw angular acceleration
            varphi_dot_dot=(F_x_r*obj.R)/obj.Iz; % wheel rotary acceleration
            
            if isnan(beta_dot) % side slip angle well defined?
                beta_dot=0; % recover side slip angle
            end


            
            % calculate xdot and gradient
            xdot  = [x_dot; y_dot; v_dot; beta_dot; psi_dot; omega_dot; x_dot_dot; y_dot_dot; psi_dot_dot; varphi_dot_dot];
            grad_xdot = zeros(obj.n);
        end
        

        function r = ref(obj, tk, xk, t_r, t_l)
            %     xk = [2,1]';
            % calculate trajectory center line
            t_c = (t_r + t_l)/2;
            % find closest trajectory point w.r.t. the vehicle
            [~,idx] = min( pdist2(xk',t_c,'seuclidean',[1 1].^0.5).^2 );
            % set target as 3 poins ahead
            idx_target = idx +3;
            % loop around when track is over
            idx_target = mod(idx_target, size(t_c,1));
            % return reference signal
            r = t_c(idx_target,:);
        end


    end
end

