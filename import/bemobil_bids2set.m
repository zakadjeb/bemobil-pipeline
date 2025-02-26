function bemobil_bids2set(bemobil_config, numericalIDs)
% This function reads in BIDS datasets using the eeglab plugin 
% "bids-matlab-tools" and reorganizes the output to be compatible with 
% BeMoBIL pipeline. 
%
% Usage
%       bemobil_bids2set(bemobil_config)
%
% In
%       config
%       see help bemobil_config documentation
%
% Out
%       none
%       reorganizes data on disk
%
% required plugins
%       modified version of SCCN bids-matlab-tools :
%               (link to be provided)
%       bva-io for brain vision data :
%               https://github.com/arnodelorme/bva-io
%
% author : seinjeung@gmail.com
%--------------------------------------------------------------------------

% input check and default value assignment 
%--------------------------------------------------------------------------

if ~isfield(bemobil_config, 'bids_data_folder')
    bemobil_config.bids_data_folder = '1_BIDS-data\';
    warning(['Config field "bids_data_folder" has not been specified- using default folder name ' bemobil_config.bids_data_folder])
end

if ~isfield(bemobil_config, 'other_data_types')
    bemobil_config.other_data_types = {'motion'};
    warning(['Config field "other_data_types" has not been specified- using default value ' bemobil_config.other_data_types{1}])
end

if ~isfield(bemobil_config, 'resample_freq')
    bemobil_config.resample_freq = 250;
    warning('Config field "resample_freq" has not been specified- using default value 250')
end

if ~isfield(bemobil_config, 'merged_filename')
    bemobil_config.merged_filename = 'merged_EEG.set';
    warning('Config field "merged_filename" has not been specified- using default value merged.set')
end


% write down the names of other data types then eeg (use BIDS suffix)
otherDataTypes  = bemobil_config.other_data_types; 

% construct the bids data directory 
bidsDir         = fullfile(bemobil_config.study_folder, bemobil_config.bids_data_folder);

% all runs and sessions are merged by default - can be optional e.g., bemobil_config.bids_mergeruns = 1; bemobil_config.bids_mergeses  = 1;
targetDir       = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder);                    % construct using existing config fields
tempDir         = fullfile(targetDir, 'temp_bids'); 

if isdir(tempDir)
    warning('Previous import seems to have been interrupted - removing temp_bids folder')
    rmdir(tempDir, 's')
end

skipFlag = false(size(numericalIDs)); 

% check if final session file names are there - if so, skip
for IDi = 1:numel(numericalIDs)
    [sesfilePath, sesfileName] = sessionfilename(targetDir, 'EEG', bemobil_config, 1, numericalIDs(IDi)); 
    if isfile(fullfile(sesfilePath, sesfileName))
        disp(['File ' sesfileName ' found - skipping import for this participant'])
        skipFlag(IDi) = true;
    end 
end

numericalIDs = numericalIDs(~skipFlag); 

if isempty(numericalIDs)
    disp('All participant data had already been converted from BIDS to .set');
    return;
end

% Import data set saved in BIDS, using a modified version of eeglab plugin 
%--------------------------------------------------------------------------
pop_importbids_mobi(bidsDir,'datatypes',otherDataTypes,'outputdir', tempDir, 'participants', numericalIDs);

% Restructure and rename the output of the import function
%--------------------------------------------------------------------------
% list all files and folders in the target folder
subDirList      = dir(tempDir);

% find all subject folders
dirFlagArray    = [subDirList.isdir];
nameArray       = {subDirList.name};
nameFlagArray   = ~contains(nameArray, '.'); % this is to exclude . and .. folders
subDirList      = subDirList(dirFlagArray & nameFlagArray);

% iterate over all subjects
for iSub = 1:numel(subDirList)
    
    subjectDir      = subDirList(iSub).name;
    sesDirList      = dir(fullfile(tempDir, subjectDir));
    
    % check if data set contains multiple sessions
    isMultiSession = any(contains({sesDirList(:).name},'ses-'));
    
    if isMultiSession
        
        % if multisession, iterate over sessions and concatenate files in EEG folder
        dirFlagArray    = [sesDirList.isdir];
        nameArray       = {sesDirList.name};
        nameFlagArray   = ~contains(nameArray, '.'); % this is to exclude . and .. folders
        sesDirList      = sesDirList(dirFlagArray & nameFlagArray);
        
        allFiles        = [];
        for iSes = 1:numel(sesDirList)
            sesDir          = sesDirList(iSes);
            sesEEGDir       = fullfile(tempDir, subjectDir, sesDir.name, 'eeg'); 
            sesBEHDir       = fullfile(tempDir, subjectDir, sesDir.name, 'beh'); 
            sesFilesEEG     = dir(sesEEGDir)';
            sesFilesBEH     = dir(sesBEHDir)';
            allFiles        = [allFiles sesFilesEEG sesFilesBEH];
        end
        
    else
        
        % for unisession, simply find all files in EEG folder
        eegDir          = fullfile(tempDir, subjectDir, 'eeg'); 
        behDir          = fullfile(tempDir, subjectDir, 'beh'); 
        allFiles        = [dir(eegDir) dir(behDir)] ;
        
    end
    
    % select only .set files
    allFiles = allFiles(contains({allFiles(:).name},'.set')) ;
    
    for iFile = 1:numel(allFiles)
        
        % rename files to bemobil convention (only eeg files for now)
        bidsName        = allFiles(iFile).name;                             % 'sub-003_task-VirtualNavigation_eeg.set';
        bidsNameSplit   = regexp(bidsName, '_', 'split');
        subjectNr       = str2double(bidsNameSplit{1}(5:end));
        bidsModality    = bidsNameSplit{end}(1:end-4);                      % this string includes modality and extension
        extension       = bidsNameSplit{end}(end-3:end);
        
        if find(strncmp(bidsNameSplit,'ses',3))
            isMultiSession      = 1; 
            sessionName         = bidsNameSplit{strncmp(bidsNameSplit,'ses',3)}(5:end);
        end
        
        if find(strncmp(bidsNameSplit, 'run',3))
            isMultiRun          = true;
            runIndex            = bidsNameSplit{strncmp(bidsNameSplit, 'run',3)}(5:end);
        else
            isMultiRun          = false; 
        end
        
        switch bidsModality
            case 'eeg'
                bemobilModality = upper(bidsModality);                      % use string 'EEG' for eeg data
                bidsFolderName  = 'eeg'; 
            case 'motion'
                bemobilModality = 'MOTION';
                bidsFolderName = 'beh';
            case 'physio'
                bemobilModality = 'PHYSIO';
                bidsFolderName = 'beh';
            otherwise
                bemobilModality = bidsModality;
                disp(['Unknown modality' bidsModality ' saved as ' bemobilModality '.set'])
        end
        
        if isMultiSession
            
            dataDir         = fullfile(tempDir, subjectDir, ['ses-' sessionName] , bidsFolderName);
            
            % move files and then remove the empty eeg folder
            newDir          = fullfile(targetDir, [bemobil_config.filename_prefix num2str(subjectNr)]);
            
            if ~isdir(newDir)
                mkdir(newDir)
            end
            
            if isMultiRun
                bemobilName     = [bemobil_config.filename_prefix, num2str(subjectNr), '_' sessionName '_' bemobilModality, '_rec', runIndex, '_old', extension];
            else
                bemobilName     = [bemobil_config.filename_prefix, num2str(subjectNr), '_' sessionName '_' bemobilModality, '_old', extension];
            end
            
            data    = pop_loadset('filepath', dataDir, 'filename', bidsName);
            pop_saveset(data, 'filepath', newDir, 'filename', bemobilName);
            
        else
            
            dataDir         = fullfile(tempDir, subjectDir, bidsFolderName);
            
            % move files and then remove the empty eeg folder
            newDir          = fullfile(targetDir, [bemobil_config.filename_prefix num2str(subjectNr)]);
            
            if ~isfolder(newDir)
                mkdir(newDir)
            end
            
            % construct the new file name 
            if isMultiRun
                bemobilName     = [bemobil_config.filename_prefix, num2str(subjectNr), '_' bemobil_config.session_names{1} '_' bemobilModality, '_rec', runIndex '_old', extension];
            else
                bemobilName     = [bemobil_config.filename_prefix, num2str(subjectNr), '_' bemobil_config.session_names{1} '_' bemobilModality '_old', extension];
            end
           
            data    = pop_loadset('filepath', dataDir, 'filename', bidsName); 
            pop_saveset(data, 'filepath', newDir, 'filename', bemobilName); 
            
        end
    end 
end

% delete the temporary directory
disp(['removing ' tempDir])
rmdir(tempDir, 's')

% now synchronize and merge the streams
%--------------------------------------------------------------------------
% list all subject directories
subDirList      = dir(targetDir); 
nameArray       = {subDirList.name};
nameFlagArray   = ~contains(nameArray, '.'); % this is to exclude . and .. folders
nameArray       = nameArray(nameFlagArray); 
subDirList      = subDirList(nameFlagArray);

% select participant data to process
subFlagArray    = true(size(nameArray)); 
if ~isempty(numericalIDs)
    for iN = 1:numel(nameArray)
        subjectNr = str2double(nameArray{iN}(numel(bemobil_config.filename_prefix) + 1:end));
        if ~ismember(subjectNr,numericalIDs)
            subFlagArray(iN) = false; 
        end
    end
    subDirList = subDirList(subFlagArray); 
end

% merge all the run files if needed
for iSub = 1:numel(subDirList)
    
    % list all files in the subject folder
    subjectFiles = dir(fullfile(targetDir, subDirList(iSub).name));
    subjectNr = str2double(subDirList(iSub).name(numel(bemobil_config.filename_prefix) + 1:end));
    
    % iterate over sessions
    for iSes = 1:numel(bemobil_config.session_names)
         
        % find all EEG data
        eegFiles = {subjectFiles(contains({subjectFiles.name}, [bemobil_config.session_names{iSes} '_EEG']) & contains({subjectFiles.name}, '_old.set')).name};
        eegFiles = natsortfiles(eegFiles); 
        
        % resample and merge EEG
        %------------------------------------------------------------------
        if isempty(bemobil_config.resample_freq)
            newSRate        = 250;
            warning('No resample frequency specified - data is still resampled to the default 250 Hz')
        else
            newSRate        = bemobil_config.resample_freq;
        end
        
        % initializa a matrix storing EEG first and last time stamps (this is used to synch other streams)
        eegTimes = NaN(2,numel(eegFiles)); 
        
        if numel(eegFiles) > 1

            % multi-run case 
            EEGFileNameWithRun  = eegFiles{1};
            nameSplit           = regexp(EEGFileNameWithRun,'_', 'split'); % remove _rec entity
            nameJoined          = join(nameSplit(1:end-2),'_');
            EEGSessionFileName  = [nameJoined{1} '_old.set'];
            
            % loop over runs 
            ALLEEG = []; CURRENTSET = [];
            for Ri = 1:numel(eegFiles)
                EEG         = pop_loadset('filepath',fullfile(targetDir, subDirList(iSub).name),'filename', eegFiles{Ri});
                eegTimes(:,Ri) = [EEG.times(1); EEG.times(end)];
                [EEG]       = resampleToTime(EEG, newSRate, EEG.times(1), EEG.times(end), 0); % resample
                [ALLEEG,EEG,CURRENTSET]  = pop_newset(ALLEEG, EEG, CURRENTSET, 'study',0);
            end
            [~, EEGMerged, ~]  = bemobil_merge(ALLEEG, EEG, CURRENTSET, 1:length(ALLEEG), EEGSessionFileName, fullfile(targetDir, [bemobil_config.filename_prefix, num2str(subjectNr)]));
            EEG                = EEGMerged;

        elseif numel(eegFiles) == 1
            EEGSessionFileName  = eegFiles{1};
            EEG                 = pop_loadset('filepath',fullfile(targetDir, subDirList(iSub).name),'filename', eegFiles{1});
            eegTimes(:,1)       = [EEG.times(1); EEG.times(end)]; 
            [EEG]               = resampleToTime(EEG, newSRate, EEG.times(1), EEG.times(end), 0); % resample 
        else
            warning(['No EEG file found in subject dir ' subDirList(iSub).name ', session ' bemobil_config.session_names{iSes}] )
        end
        
        EEG = eeg_checkset(EEG); 
        
        % save merged EEG file for the session
        EEG = pop_saveset(EEG, 'filename',[EEGSessionFileName(1:end-8) EEGSessionFileName(end-3:end)],'filepath',fullfile(targetDir, subDirList(iSub).name));
        disp(['Saved session file ' EEGSessionFileName(1:end-8) EEGSessionFileName(end-3:end)])
        

        
        % now iterate over other data types
        for iType = 1:numel(otherDataTypes)
            
            switch otherDataTypes{iType}
                case 'motion'
                    bemobilModality = 'MOTION';
                case 'physio'
                    bemobilModality = 'PHYSIO';
                otherwise
                    bemobilModality = otherDataTypes{iType};
                    disp(['Unknown modality' otherDataTypes{iType} ', looking for ' otherDataTypes{iType} '.set'])
            end
            
            % find all data of the type
            dataFiles = {subjectFiles(contains({subjectFiles.name}, [bemobil_config.session_names{iSes} '_' bemobilModality]) & contains({subjectFiles.name}, '_old.set')).name};
            
         
            % resample and merge DATA
            %--------------------------------------------------------------
            if isempty(bemobil_config.resample_freq)
                newSRate        = EEG.srate;
                warning(['No resample frequency specified -' bemobilModality 'data is still resampled to match EEG srate, ' num2str(newSRate) 'Hz'])
            else
                newSRate        = bemobil_config.resample_freq;
            end
            
            if numel(eegFiles) ~= numel(dataFiles)
                warning('Number of EEG and other data files do not match within a session')
            end
            
            if numel(dataFiles) > 1
                
                DATAFileNameWithRun     = dataFiles{1};
                nameSplit               = regexp(DATAFileNameWithRun,'_', 'split'); % remove _run entity
                nameJoined              = join(nameSplit(1:end-2),'_');
                DATASessionFileName      = [nameJoined{1} '_old.set'];
                
                % loop over runs
                ALLDATA = []; CURRENTSET = [];
                for Ri = 1:numel(dataFiles)
                    DATA         = pop_loadset('filepath',fullfile(targetDir, subDirList(iSub).name),'filename', dataFiles{Ri});
                    DATA         = unwrapAngles(DATA); % unwrap angles before resampling
                    % start time has to be buffered before data can be synched to EEG 
                    DATA.times   = DATA.times + DATA.etc.starttime*1000;
                    [DATA]       = resampleToTime(DATA, newSRate, eegTimes(1,Ri), eegTimes(2,Ri), DATA.etc.starttime);
                    DATA         = wrapAngles(DATA);
                    [ALLDATA,DATA,CURRENTSET]  = pop_newset(ALLDATA, DATA, CURRENTSET, 'study',0);
                end
                [~, DATAMerged, ~]  = bemobil_merge(ALLDATA, DATA, CURRENTSET, 1:length(ALLDATA), DATASessionFileName, fullfile(targetDir, [bemobil_config.filename_prefix, num2str(subjectNr)]));
                DATA             = DATAMerged;
                
            elseif numel(dataFiles) == 1
                DATASessionFileName  = dataFiles{1};
                DATA             = pop_loadset('filepath', fullfile(targetDir, subDirList(iSub).name), 'filename', dataFiles{1});
                DATA             = unwrapAngles(DATA);
                % start time has to be buffered before data can be synched to EEG
                DATA.times   = DATA.times;
                [DATA]           = resampleToTime(DATA, newSRate, eegTimes(1,1), eegTimes(2,1), DATA.etc.starttime);
                DATA             = wrapAngles(DATA);
            else
                warning(['No file of modality ' bemobilModality ' found in subject dir ' subDirList(iSub).name ', session ' bemobil_config.session_names{iSes}] )
            end
            % save merged data file for the session
            DATA = pop_saveset(DATA, 'filename', [DATASessionFileName(1:end-8) DATASessionFileName(end-3:end)],'filepath',fullfile(targetDir, subDirList(iSub).name));
            disp(['Saved session file ' [DATASessionFileName(1:end-8) DATASessionFileName(end-3:end)]])
        end
    end
    
    % remove unnecessary files prior to merging
    subjectFiles = dir(fullfile(targetDir, subDirList(iSub).name));
    toDelete = {subjectFiles(contains({subjectFiles.name}, '_old.fdt') | contains({subjectFiles.name}, '_old.set')).name};
    
    for iD = 1:numel(toDelete)
        delete(fullfile(targetDir, subDirList(iSub).name, toDelete{iD}));
    end
    
    % merge EEG sessions
    %----------------------------------------------------------------------
    if numel(bemobil_config.session_names) > 1
        ALLEEG = []; CURRENTSET = [];
        for Si = 1:numel(bemobil_config.session_names)
            [outPath, outName] = sessionfilename(targetDir,'EEG', bemobil_config, Si, subjectNr);
            EEG         = pop_loadset('filepath',outPath,'filename',outName);
            [ALLEEG,EEG,CURRENTSET]  = pop_newset(ALLEEG, EEG, CURRENTSET, 'study',0);
        end
        [~, EEG_merged, ~]  = bemobil_merge(ALLEEG, EEG, CURRENTSET, 1:length(ALLEEG), [bemobil_config.filename_prefix, num2str(subjectNr), '_' bemobil_config.merged_filename], fullfile(targetDir, [bemobil_config.filename_prefix, num2str(subjectNr)]));
    end
    
end

disp('BIDS to .set conversion finished')

end


function [outPath, outName] = sessionfilename(targetDir, modality, bemobil_config, sesnr, subnr)

outName     = [bemobil_config.filename_prefix, num2str(subnr), '_', bemobil_config.session_names{sesnr} '_' modality '.set'];
outPath     = fullfile(targetDir,[bemobil_config.filename_prefix, num2str(subnr)]); 

end

function [outEEG] = resampleToTime(EEG, newSRate, tFirst, tLast, offset)
% offset is in seconds 
%--------------------------------------------------------------------------
% check if any row is all zeros - use nearest interp if so
hasNonZero = any(EEG.data,2);
if any(hasNonZero == 0)
    resampleMethod = 'nearest'; 
else
    resampleMethod = 'pchip'; 
end

% save old times
oldTimes                = EEG.times; 

% Note that in fieldtrip time is in seconds
newTimes                = (tFirst:1000/newSRate:tLast)/1000;

resamplecfg.time        = {newTimes};
resamplecfg.detrend     = 'no';
resamplecfg.method      = resampleMethod; 
resamplecfg.extrapval   = nan; 
EEG.group = 1; EEG.condition = 1;
ftData                  = eeglab2fieldtrip( EEG, 'raw', 'none' );
ftData.time{1}          = ftData.time{1} + offset; 
resampledData           = ft_resampledata(resamplecfg, ftData);
EEG.data                = resampledData.trial{1};
EEG.srate               = newSRate;
EEG.times               = newTimes*1000; % convert back to miliseconds
EEG.pnts                = size(EEG.data,2);
EEG.urevent             = EEG.event;

% sometimes broken recordings lead to NaN values in the latency fields
for iE = 1:numel(EEG.event)
    if isnan(EEG.urevent(iE).latency)
        warning(['NaN value detected in event ' num2str(iE)])
    else
        EEG.event(iE).latency        = find(EEG.times > oldTimes(round(EEG.urevent(iE).latency)),1,'first');
    end
end

EEG.setname = EEG.filename(1:end-8);

% checkset
outEEG = eeg_checkset(EEG, 'makeur');

end

function [DATA] = unwrapAngles(DATA)

% unwrap any kind of angular data before resampling
angleind = [];
for Ci = 1:numel(DATA.chanlocs)
    if ischar(DATA.chanlocs(Ci).units)
        if  contains(DATA.chanlocs(Ci).units, 'rad')
            angleind =  [angleind Ci];
        end
    end
end

DATA.data(angleind,:)   = unwrap(DATA.data(angleind,:),[],2);

end


function [DATA] = wrapAngles(DATA)

% wrap any kind of angular data before resampling
angleind = [];
for Ci = 1:numel(DATA.chanlocs)
    if ~isempty(DATA.chanlocs(Ci).units)
        if  contains(DATA.chanlocs(Ci).units, 'rad')
            angleind =  [angleind Ci];
        end
    end
end

DATA.data(angleind,:)   = wrapToPi(DATA.data(angleind,:));

end