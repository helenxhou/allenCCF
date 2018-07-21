% ------------------------------------------------------------------------
%          Display Probe Track
% ------------------------------------------------------------------------

%% ENTER PARAMETERS AND FILE LOCATION

% file location of probe points
processed_images_folder = 'C:\Drive\Histology\for tutorial - sample data\SS096_done\processed';

% directory of reference atlas files
annotation_volume_location = 'C:\Drive\Histology\for tutorial\annotation_volume_10um_by_index.npy';
structure_tree_location = 'C:\Drive\Histology\for tutorial\structure_tree_safe_2017.csv';

% name of the saved probe points
probe_save_name_suffix = '_tutorial';

% either set to 'all' or a list of indices from the clicked probes in this file, e.g. [2,3]
probes_to_analyze = 'all';

% -----------
% parameters
% -----------
% how far into the brain did you go, either for each probe or just one number for all -- in mm
probe_lengths = 5.0; 

% from the bottom tip, how much of the probe contained recording sites -- in mm
active_probe_length = 3.84;

% distance queried for confidence metric -- in um
probe_radius = 100; 

% overlay the distance between parent regions in gray (this takes a while)
show_parent_category = false; 

% plot this far or to the bottom of the brain, whichever is shorter -- in mm
distance_past_tip_to_plot = .3;

% set scaling e.g. based on lining up the ephys with the atlas
% set to *false* to get scaling automatically from the clicked points
scaling_factor = 1.0; 

% show a table of regions that the probe goes through, in the console
show_region_table = true;
                                        


% close all



%% GET AND PLOT PROBE VECTOR IN ATLAS SPACE

% -----------------------------------------------
% load the reference annotations and probe points
% -----------------------------------------------
% load the reference brain annotations
if ~exist('av','var') || ~exist('st','var')
    disp('loading reference atlas...')
    av = readNPY(annotation_volume_location);
    st = loadStructureTree(structure_tree_location);
end

% load probe points
probePoints = load(fullfile(processed_images_folder, ['probe_points' probe_save_name_suffix]));
ProbeColors = [1 1 1; 1 .75 0;  .3 1 1; .4 .6 .2; 1 .35 .65; .7 .7 1; .65 .4 .25; .7 .95 .3; .7 0 0; .6 0 .7; 1 .6 0]; 
% order of colors: {'white','gold','turquoise','fern','bubble gum','overcast sky','rawhide', 'green apple','purple','orange','red'};
fwireframe = [];

% determine which probes to analyze
if strcmp(probes_to_analyze,'all')
    probes = 1:size(probePoints.pointList.pointList,1);
else
    probes = probes_to_analyze;
end 


%% ----------------------------------------------------------------
% plot each probe -- first find its trajectory in reference space
% ----------------------------------------------------------------
for selected_probe = probes
    
% get the probe points for the currently analyzed probe    
curr_probePoints = probePoints.pointList.pointList{selected_probe,1}(:, [3 2 1]);

% get user-defined probe length from experiment
if length(probe_lengths) > 1
    probe_length = probe_lengths(selected_probe);
else
    probe_length = probe_lengths;
end

% get the scaling-factor method to use
if scaling_factor
    use_tip_to_get_reference_probe_length = false;
    reference_probe_length = probe_length * scaling_factor;
    disp(['probe scaling of ' num2str(scaling_factor) ' determined by user input']);    
else
    use_tip_to_get_reference_probe_length = true;
    disp(['getting probe scaling from histology data...']);
end

% get line of best fit through points
% m is the mean value of each dimension; p is the eigenvector for largest eigenvalue
[m,p,s] = best_fit_line(curr_probePoints(:,1), curr_probePoints(:,2), curr_probePoints(:,3));


% ensure proper orientation: want 0 at the top of the brain and positive distance goes down into the brain
if p(2)<0
    p = -p;
end

% determine "origin" at top of brain -- step upwards along tract direction until tip of brain / past cortex
ann = 10;
isoCtxId = num2str(st.id(strcmp(st.acronym, 'Isocortex')));
gotToCtx = false;
while ~(ann==1 && gotToCtx)
    m = m-p; % step 10um, backwards up the track
    ann = av(round(m(1)),round(m(2)),round(m(3))); %until hitting the top
    if ~isempty(strfind(st.structure_id_path{ann}, isoCtxId))
        % if the track didn't get to cortex yet, keep looking...
        gotToCtx = true;
    end
end

% plot brain grid
fwireframe = plotBrainGrid([], [], fwireframe); hold on; 
fwireframe.InvertHardcopy = 'off';

% plot probe points
hp = plot3(curr_probePoints(:,1), curr_probePoints(:,3), curr_probePoints(:,2), '.','linewidth',2, 'color',[ProbeColors(selected_probe,:) .2],'markers',10);

% plot brain entry point
plot3(m(1), m(3), m(2), 'k*','linewidth',1)

% use the deepest clicked point as the tip of the probe, if no scaling provided
if use_tip_to_get_reference_probe_length
    % find length of probe in reference atlas space
    [depth, tip_index] = max(curr_probePoints(:,2));
    reference_probe_length_tip = sqrt(sum((curr_probePoints(tip_index,:) - m).^2)); 
    
    % and the corresponding scaling factor
    shrinkage_factor = (reference_probe_length_tip / 100) / probe_length;
    
    % display the scaling
    disp(['probe length of ' num2str(reference_probe_length_tip/100) ' mm in reference atlas space compared to a reported ' num2str(probe_length) ' mm']);
    disp(['probe scaling of ' num2str(shrinkage_factor)]); disp(' ');
    
    % plot line the length of the probe in reference space
    rpl = round(reference_probe_length_tip);
    
% use user-defined probe plotting length or scaling factor    
else 
    rpl = round(reference_probe_length * 100); 
end

% find the percent of the probe occupied by electrodes
percent_of_tract_with_active_sites = min([active_probe_length / probe_length, 1.0]);
active_site_start = rpl*(1-percent_of_tract_with_active_sites);
apl = round([active_site_start  rpl]);

% plot line the length of the active probe sites in reference space
plot3(m(1)+p(1)*[apl(1) apl(2)], m(3)+p(3)*[apl(1) apl(2)], m(2)+p(2)*[apl(1) apl(2)], ...
    'Color', ProbeColors(selected_probe,:), 'LineWidth', 1);
% plot line the length of the entire probe in reference space
plot3(m(1)+p(1)*[1 rpl], m(3)+p(3)*[1 rpl], m(2)+p(2)*[1 rpl], ...
    'Color', ProbeColors(selected_probe,:), 'LineWidth', 1, 'LineStyle',':');


%% ----------------------------------------------------------------
% Get and plot brain region labels along the extent of each probe
% ----------------------------------------------------------------

% convert error radius into mm
error_length = round(probe_radius / 10);

% find and regions the probe goes through, confidence in those regions, and plot them
borders_table = plotDistToNearestToTip(m, p, av, st, rpl, error_length, active_site_start, distance_past_tip_to_plot, show_parent_category, show_region_table); % plots confidence score based on distance to nearest region along probe
title(['Probe ' num2str(selected_probe)],'color',ProbeColors(selected_probe,:))

pause(.05)
end
