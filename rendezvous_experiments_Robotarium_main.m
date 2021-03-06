%% This is the main file to conduct experiments with several consensus control (rendezvous) algorithms of N robots in the Robotarium testbed
%Ramviyas Parasuraman, ramviyas@purdue.edu. 
close all;

global sensing_range error_bearing error_distance uni_to_si_states si_to_uni_dyn si_pos_controller G N desired_distance;

%% Choose your Rendezvous algorithm
% Newly Proposed Weighted Bearing Controllers
algorithm = 'weighted_bearing_consensus_using_RSS_and_DOA'; % It uses the DOA of RSS and the RSS form wireless nework measurements as control inputs
%algorithm = 'weighted_bearing_consensus_using_Range_and_Bearings'; % It uses both range and bearing measurements from any sensors as control inputs

% Baseline Algorithm - Coordinates based consensus(Rendezvous) algorithms
%algorithm = 'coordinates_based_rendezvous' ; % It relies on the full coordinates (relative positions) of neighbor robots
%algorithm = 'coordinates_based_connectivity_preserving_rendezvous' ; % It is similar to the above but uses weights (artificial potential fields)

% State of the Art (SOTA) Bearing-only consensus(Rendezvous) algorithms
%algorithm = 'bearing_only_rendezvous_using_all_bearings';
%algorithm = 'bearing_only_rendezvous_using_min_and_max_bearings';
%algorithm = 'bearing_only_rendezvous_using_enclosing_circles';

% Other possible consensus controllers 
%algorithm = 'bearing_only_rendezvous_using_average_bearing';
%algorithm = 'coordinates_based_rendezvous_with_mean_velocity';
%algorithm = 'coordinates_based_rendezvous_with_max_velocity';
%algorithm = 'coordinates_based_rendezvous_with_min_velocity';

fH = str2func(algorithm); % function handle for the chosen rendezvous algorithm

%% Get Robotarium object used to communicate with the robots/simulator
rb = RobotariumBuilder();
N=20; % Number of agents/robots
% Build the Robotarium simulator object!
r = rb.set_number_of_agents(N).set_save_data(false).build();
figure_robotarium = figure(1); movegui('northeast'); movegui('onscreen');
%title('Rendezvous algorithm experimented in Robotarium testbed');

%% Experiment parameters
desired_distance = 0.1; % desired inter-agent distance range to realize stop condition
desired_energy = 0.2; % desired value of the Lyapunov candidate energy function (not used)
sensing_range = 0.8; % Sensing radius within which robot i detects robot j (same for all the robots)
error_bearing = 0.0; % Standard deviations of the bearing measurment error (radians)
error_distance = 0.0; % Standard deviations of the distance measurment error (m)
safety_radius = 0.04; % safety radius for collision avoidance between robots
dxmax = 1; % if normalize_velocities is used

%% Flags to use specific parts of the code
collision_avoidance = 0; % To enable/disable barrier certificates
normalize_velocities = 1; % To normalize the velocities (recommended)
update_network_topology = 1; % To enable/disable the update of connected graph (dynamically) in every iteration
plot_initial_graph = 0; % To plot initial connected graph
plot_dynamic_graph = 0; % To plot updated connected graph in every iteration
plot_robot_index = 1; % To enable/disable the display of robot index on top of each robot in the Robotarium figure
plot_robot_trajectory = 1; % To enable/disable the display of robot trajectory in the Robotarium figure
plot_robot_initialposition = 1; % To enable/disable the display of robot initial position in the Robotarium figure

%% Grab tools we need to convert from single-integrator to unicycle dynamics
%Gains for the transformation from single-integrator to unicycle dynamics
linearVelocityGain = 2; %1
angularVelocityGain = pi;
transformation_gain = 0.06;

% Gain for the diffeomorphism transformation between single-integrator and
% unicycle dynamics
[~, uni_to_si_states] = create_si_to_uni_mapping('ProjectionDistance', transformation_gain);
si_to_uni_dyn = create_si_to_uni_mapping2('LinearVelocityGain', linearVelocityGain, 'AngularVelocityLimit', angularVelocityGain);
% Single-integrator position controller
si_pos_controller = create_si_position_controller('XVelocityGain', 2, 'YVelocityGain', 2);
% Collision avoidance - barrier certificates
si_barrier_cert = create_si_barrier_certificate('SafetyRadius', safety_radius);

%% Initialize the robots to fixed positions
%initial_positions = [0 0.4 0.5 0.4 -0.1 -0.3 -0.5 -0.7 0 1 -1 -1 0.3 -0.5 0.9; 0.3 0.9 1.1 -1 -0.2 -0.9 -0.3 -1 1.2 -1.2 0.2 -0.9 -0.4 0.6 1];
initial_positions = r.poses(1:2,:) *3; % For random initial positions
r = initialize_robot_positions(r,N,initial_positions);


%% Finding the connected tree based on initial positions of the robots
x = r.get_poses();
xi = uni_to_si_states(x);
r.step();
[L,G] = GetConnectedGraph(x(1:2,:),sensing_range); % Finding the initial connected Graph

%% Initiating connected graph figure window
if(plot_initial_graph == 1)
    figure_graph = figure(2); plot(G); title('Initial Network Topology');
    xlim([-3 3]);
    ylim([-3 3]);
    movegui('northwest');
end

%% Experiments initialize
max_iterations = 1000; % the number of iterations for the experiment

% Initialize velocity vector for agents.  Each agent expects a 2 x 1
% velocity vector containing the linear and angular velocity, respectively.
dxi = zeros(2, N);

previous_xi = xi; % A temporary variable to store the position values
distance_travelled = zeros(1,N); % total distance traveled by each robot - Performance evaluation metric
iteration_at_stopcondition = 0; % number of iteration at which the stop condition is reached
iteration_at_minenergy = 0; % number of iteration at which the energy function values is the minimum (less than a threshold)
energy = zeros(1,max_iterations); % The value of the Energy function which is sum of all distances between the connected nodes
mycols = jet(N); % To display colored trajectory for each robot (if plot_robot_trajectory is set)
fig_index = figure_robotarium;
fig_traj = figure_robotarium;

% Display the robot's initial position trajectory in the Robotarium figure
if(plot_robot_initialposition == 1)  
    %fig_traj = set(0,'CurrentFigure',r.figure_handle);
    for i=1:N
        fig_traj = plot(x(1,i),x(2,i),'o','Color',mycols(i,:));
    end
end
    
disp('Rendezvous process initiated - displaying the number of iterations');

% Display the title text
set(0,'CurrentFigure',r.figure_handle);
alg_string = regexprep(algorithm,'_',' ');
alg_string = regexprep(alg_string,'\s*.','${upper($0)}');
text(-1.4,1.4,alg_string,'FontSize',8,'Color','red','FontWeight','Bold', 'Interpreter', 'none');

    
%Iteration starts here (for the previously specified number of iterations)
for t = 1:max_iterations
    disp(t) % to display the iteration number
    %stop_condition = 1; % This variable is to define the stop condition. If it's 1 - then stop the iteration/experiment 

    set(0,'CurrentFigure',r.figure_handle);
    fig_iter = text(-1.4,-1.4,strcat('Iteration :',' ',num2str(t)),'FontSize',10,'Color','red','FontWeight','Bold');

    % Retrieve the most recent poses from the Robotarium.  The time delay is
    % approximately 0.033 seconds in Robotarium
    x = r.get_poses(); % Get unicycle coordinates (x,y,theta)
    xi = uni_to_si_states(x); % convert the unicycle pose to SI units (x,y)
    
    % Display the robot's index on top of each robot in the Robotarium
    % figure
    if(plot_robot_index == 1)  
        for i=1:N
            set(0,'CurrentFigure',r.figure_handle);
            fig_index(i) = text(x(1,i),x(2,i)+0.04,num2str(i),'FontSize',10,'Color','red','FontWeight','Bold');
        end
    end

    % Display the robot's trajectory in the Robotarium figure
    if(plot_robot_trajectory == 1)  
        for i=1:N
            set(0,'CurrentFigure',r.figure_handle);
            fig_traj(i) = plot(x(1,i),x(2,i),'.--','Color',mycols(i,:));
        end
    end
    
    % Update the connected tree dynamically
    if (update_network_topology == 1)
        [L,G] = GetConnectedGraph(x(1:2,:),sensing_range); % Finding the initial connected Graph
    end
    
    %% Chosen Rendezvous Algorithm
    [dxi,stop_condition,energy(t)] = fH(L,xi);
    
    %% Plotting the connected graph
    if(plot_dynamic_graph == 1)
        set(0,'CurrentFigure',figure_graph);   
        plot(G); title('Dynamic Network Topology'); 
        xlim([-3 3]);
        ylim([-3 3]);
    end
        
    %% Normalizing the velocity limits
    if(normalize_velocities == 1)
        for i = 1:N
            if norm(dxi(:,i)) > dxmax
                dxi(:,i) = dxi(:,i)/norm(dxi(:,i))*dxmax;
            end
        end
    end
    %% Utilize barrier certificates
    
    if(collision_avoidance == 1)
        dxi = si_barrier_cert(dxi, x);
    end
    
    % Transform the single-integrator to unicycle dynamics using the transformation we created earlier
    dxu = si_to_uni_dyn(dxi, x);
    
    %% Send velocities to agents
    
    % Set velocities of agents 1,...,N
    r.set_velocities(1:N, dxu);
    
    % Send the previously set velocities to the agents.  This function must be called!    
    r.step();
    
    %% Performance evaluation metrics
    % Calculate the distance travelled in each iteration
    for i=1:N
        distance_travelled(i) = distance_travelled(i) + norm(xi(:,i)-previous_xi(:,i));
    end
    previous_xi = xi;
    
    %if (stop_condition == 1 && length(leaves) == N-1)
    if ((stop_condition == 1) && (iteration_at_stopcondition == 0))
        display('Stop condition (all inter-robot distances within 0.1m) reached ');
        iteration_at_stopcondition = t;
    end
    
    if((energy(t) <= desired_energy) && (iteration_at_minenergy == 0))
        display('Minimum energy condition (E<=0.2) reached');
        iteration_at_minenergy = t;
    end
    
    if(plot_robot_index == 1)  
        delete(fig_index); % delete the text objects (robot indices) on the Robotarium figure
    end
    
    delete(fig_iter);
end

% Though we didn't save any data, we still should call r.call_at_scripts_end() after our
% experiment is over!
r.call_at_scripts_end();

%print(figure_robotarium,'RobotariumFigure','-depsc');