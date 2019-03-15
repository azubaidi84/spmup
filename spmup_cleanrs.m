function clean_data = spmup_cleanrs(rsfMRI,T1w,skip)

% simplest routine to cleanup resting fMRI data 
% --------------------------------------------
% preprocessing using SPM routines
% + despiking, motion, censoring based on framewise displacement, and
% nuisance (white matter/CSF) regression + global scaling
%
% Since SPM is used to compute the regression, globals are accounted for.
% This is not GSR because each voxel is scaled by the globals, while GRS is
% a local covariation model.

%% check inputs
assert(exist(rsfMRI,'file')==2,'resting state input data do not exist')
assert(exist(T1w,'file')==2,'anatomical input data do not exist')

% need the json file
[fpath,fname,ext]=fileparts(rsfMRI);
subindex = findstr(fpath,'sub-');
if exist([fpath filesep fname '.json'],'file') == 2
    rs_param = spm_jsonread([fpath filesep fname '.json']);
elseif exist([fpath(1:subindex-1) 'task-rest_bold.json'],'file') == 2 % could be at BIDS dir root
    rs_param = spm_jsonread([fpath(1:subindex-1) 'task-rest_bold.json']);
else
    error('there is no json file associated to the resting state data, please revise file')
end

% unzip if needed
newpath = [fpath(1:strfind(fpath,'sub-')-1) 'derivatives' filesep ...
        fpath(strfind(fpath,'sub-'):strfind(rsfMRI,'func')+3)];
if strcmp(ext,'.gz')
    gunzip(rsfMRI,newpath)
    rsfMRI = [newpath filesep fname];
    fpath =fileparts(rsfMRI);
else
    if ~exist(newpath,'dir')
        mkdir(newpath);
    end
   copyfile(rsfMRI,[newpath filesep fname ext]);
   rsfMRI = [newpath filesep fname ext];
   fpath =fileparts(rsfMRI);
end

[apath,aname,aext]=fileparts(T1w);
newpath = [apath(1:strfind(apath,'sub-')-1) 'derivatives' filesep ...
        apath(strfind(apath,'sub-'):strfind(T1w,'anat')+3)];
if strcmp(aext,'.gz')
    gunzip(T1w,newpath);
    T1w = [newpath filesep aname];
else
    if ~exist(newpath,'dir')
        mkdir(newpath);
    end
   copyfile(T1w,[newpath filesep aname aext]);
   T1w = [newpath filesep aname aext];
end
clear apath aname aext

% initialize SPM
spm_jobman('initcfg');
spm_root = fileparts(which('spm'));
spm('Defaults','fmri')

%% Prepare the data

% skip images
% ------------
if skip > 0
    In =  spm_file_split(rsfMRI);
    Out = In(skip+1:end);
    V = spm_file_merge(Out,rsfMRI);
    for img =1:size(In,1)
        delete(In(img).fname);
    end
    clear In Out
end

%% Pre-processing
% 1. Slice Timing and Realignment to get motion parameters 
V = spm_vol(rsfMRI);
for v=1:size(V,1)
    filesin{v} = [V(v).fname ',' num2str(v)];
end
matlabbatch{1}.spm.temporal.st.scans{1} = filesin';
matlabbatch{1}.spm.temporal.st.nslices  = length(rs_param.SliceTiming);
matlabbatch{1}.spm.temporal.st.tr       = rs_param.RepetitionTime;
matlabbatch{1}.spm.temporal.st.ta       = rs_param.RepetitionTime-(rs_param.RepetitionTime/2);
matlabbatch{1}.spm.temporal.st.so       = rs_param.SliceTiming;
matlabbatch{1}.spm.temporal.st.refslice = rs_param.SliceTiming(end);
matlabbatch{1}.spm.temporal.st.prefix   = 'st';

matlabbatch{2}.spm.spatial.realign.estwrite.data{1}(1)       = ...
    cfg_dep('Slice Timing: Slice Timing Corr. Images (Sess 1)', substruct('.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('()',{1}, '.','files'));
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.quality = 1;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.sep     = 4;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.fwhm    = 5;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.rtm     = 1;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.interp  = 2;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.wrap    = [0 0 0];
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.weight  = '';
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.which   = [2 1];
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.interp  = 4;
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.wrap    = [0 0 0];
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.mask    = 1;
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.prefix  = 'r';

% coregister anatomical to mean EPI
matlabbatch{3}.spm.spatial.coreg.estwrite.ref(1)             = ...
    cfg_dep('Realign: Estimate & Reslice: Mean Image', substruct('.','val', '{}',{2}, '.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','rmean'));
matlabbatch{3}.spm.spatial.coreg.estwrite.source             = {T1w};
matlabbatch{3}.spm.spatial.coreg.estwrite.other = {''};
matlabbatch{3}.spm.spatial.coreg.estwrite.eoptions.cost_fun  = 'nmi';
matlabbatch{3}.spm.spatial.coreg.estwrite.eoptions.sep       = [4 2];
matlabbatch{3}.spm.spatial.coreg.estwrite.eoptions.tol       = [0.02 0.02 0.02 0.001 0.001 0.001 0.01 0.01 0.01 0.001 0.001 0.001];
matlabbatch{3}.spm.spatial.coreg.estwrite.eoptions.fwhm      = [7 7];
matlabbatch{3}.spm.spatial.coreg.estwrite.roptions.interp    = 4;
matlabbatch{3}.spm.spatial.coreg.estwrite.roptions.wrap      = [0 0 0];
matlabbatch{3}.spm.spatial.coreg.estwrite.roptions.mask      = 0;
matlabbatch{3}.spm.spatial.coreg.estwrite.roptions.prefix    = 'r';

% segment
matlabbatch{4}.spm.spatial.preproc.channel.vols(1) = ...
    cfg_dep('Coregister: Estimate & Reslice: Resliced Images', substruct('.','val', '{}',{3}, '.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','rfiles'));
matlabbatch{4}.spm.spatial.preproc.channel.biasreg           = 0.001;
matlabbatch{4}.spm.spatial.preproc.channel.biasfwhm          = 60;
matlabbatch{4}.spm.spatial.preproc.channel.write             = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(1).tpm             = {[spm_root filesep 'tpm' filesep 'TPM.nii,1']};
matlabbatch{4}.spm.spatial.preproc.tissue(1).ngaus           = 2;
matlabbatch{4}.spm.spatial.preproc.tissue(1).native          = [1 0];
matlabbatch{4}.spm.spatial.preproc.tissue(1).warped          = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(2).tpm             = {[spm_root filesep 'tpm' filesep 'TPM.nii,2']};
matlabbatch{4}.spm.spatial.preproc.tissue(2).ngaus           = 2;
matlabbatch{4}.spm.spatial.preproc.tissue(2).native          = [1 0];
matlabbatch{4}.spm.spatial.preproc.tissue(2).warped          = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(3).tpm             = {[spm_root filesep 'tpm' filesep 'TPM.nii,3']};
matlabbatch{4}.spm.spatial.preproc.tissue(3).ngaus           = 2;
matlabbatch{4}.spm.spatial.preproc.tissue(3).native          = [1 0];
matlabbatch{4}.spm.spatial.preproc.tissue(3).warped          = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(4).tpm             = {[spm_root filesep 'tpm' filesep 'TPM.nii,4']};
matlabbatch{4}.spm.spatial.preproc.tissue(4).ngaus           = 3;
matlabbatch{4}.spm.spatial.preproc.tissue(4).native          = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(4).warped          = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(5).tpm             = {[spm_root filesep 'tpm' filesep 'TPM.nii,5']};
matlabbatch{4}.spm.spatial.preproc.tissue(5).ngaus           = 4;
matlabbatch{4}.spm.spatial.preproc.tissue(5).native          = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(5).warped          = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(6).tpm             = {[spm_root filesep 'tpm' filesep 'TPM.nii,6']};
matlabbatch{4}.spm.spatial.preproc.tissue(6).ngaus           = 2;
matlabbatch{4}.spm.spatial.preproc.tissue(6).native          = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(6).warped          = [0 0];
matlabbatch{4}.spm.spatial.preproc.warp.mrf                  = 1;
matlabbatch{4}.spm.spatial.preproc.warp.cleanup              = 1;
matlabbatch{4}.spm.spatial.preproc.warp.reg                  = [0 0.001 0.5 0.05 0.2];
matlabbatch{4}.spm.spatial.preproc.warp.affreg               = 'mni';
matlabbatch{4}.spm.spatial.preproc.warp.fwhm                 = 0;
matlabbatch{4}.spm.spatial.preproc.warp.samp                 = 3;
matlabbatch{4}.spm.spatial.preproc.warp.write                = [0 0];

% make a brain mask
matlabbatch{5}.spm.util.imcalc.input(1)       = cfg_dep('Segment: c1 Images', substruct('.','val', '{}',{4}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','tiss', '()',{1}, '.','c', '()',{':'}));
matlabbatch{5}.spm.util.imcalc.input(2)       = cfg_dep('Segment: c2 Images', substruct('.','val', '{}',{4}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','tiss', '()',{2}, '.','c', '()',{':'}));
matlabbatch{5}.spm.util.imcalc.input(3)       = cfg_dep('Segment: c3 Images', substruct('.','val', '{}',{4}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','tiss', '()',{3}, '.','c', '()',{':'}));
matlabbatch{5}.spm.util.imcalc.output         = [fpath filesep 'brain_mask.nii'];
matlabbatch{5}.spm.util.imcalc.outdir         = {''};
matlabbatch{5}.spm.util.imcalc.expression     = '(i1+i2+i3)>0';
matlabbatch{5}.spm.util.imcalc.var            = struct('name', {}, 'value', {});
matlabbatch{5}.spm.util.imcalc.options.dmtx   = 0;
matlabbatch{5}.spm.util.imcalc.options.mask   = 0;
matlabbatch{5}.spm.util.imcalc.options.interp = -4;
matlabbatch{5}.spm.util.imcalc.options.dtype  = 4;
realigned_data = spm_jobman('run',matlabbatch); clear matlabbatch;

%% Regress

% get nuisance regressors
[FD,RMS,motion]      = spmup_FD(cell2mat(realigned_data{2}.sess.rpfile),[],'figure','save');
censoring_regressors = spmup_censoring([FD RMS]);% get censoring regressors
[fpath,fname,ext]    = fileparts(cell2mat(realigned_data{2}.sess.rfiles(1,:)));
rsfMRI               = [fpath filesep fname '.nii'];
nuisances            = spmup_nuisance(rsfMRI,cell2mat(realigned_data{4}.tiss(2).c),cell2mat(realigned_data{4}.tiss(3).c));
derivatives          = [zeros(1,2);diff([nuisances.WM nuisances.CSF])];

if sum(censoring_regressors(:))~=0 || ~isempty(censoring_regressors)
    design = [motion nuisances.WM nuisances.CSF derivatives censoring_regressors];
else
    design = [motion nuisances.WM nuisances.CSF derivatives];
end
save([fpath filesep 'design.txt'],'design','-ascii','-double')

% Regress (and filter)
mkdir([fpath filesep 'regression'])
matlabbatch{1}.spm.stats.fmri_spec.dir            = {[fpath filesep 'regression']};
matlabbatch{1}.spm.stats.fmri_spec.timing.units   = 'scans';
matlabbatch{1}.spm.stats.fmri_spec.timing.RT      = rs_param.RepetitionTime;
matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t  = length(rs_param.SliceTiming);
matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t0 = ceil(length(rs_param.SliceTiming)/2);

V = spm_vol(rsfMRI);
for v=1:size(V,1)
    matlabbatch{1}.spm.stats.fmri_spec.sess.scans(v,:) = {[V(v).fname ',' num2str(v)]};
end
matlabbatch{1}.spm.stats.fmri_spec.sess.cond        = struct('name', {}, 'onset', {}, 'duration', {}, 'tmod', {}, 'pmod', {}, 'orth', {});
matlabbatch{1}.spm.stats.fmri_spec.sess.multi       = {''};
matlabbatch{1}.spm.stats.fmri_spec.sess.regress     = struct('name', {}, 'val', {});
matlabbatch{1}.spm.stats.fmri_spec.sess.multi_reg   = {[fpath filesep 'design.txt']};
matlabbatch{1}.spm.stats.fmri_spec.sess.hpf         = 1000;
matlabbatch{1}.spm.stats.fmri_spec.fact             = struct('name', {}, 'levels', {});
matlabbatch{1}.spm.stats.fmri_spec.bases.hrf.derivs = [0 0];
matlabbatch{1}.spm.stats.fmri_spec.volt             = 1;
matlabbatch{1}.spm.stats.fmri_spec.global           = 'None';
matlabbatch{1}.spm.stats.fmri_spec.mthresh          = 0.2;
matlabbatch{1}.spm.stats.fmri_spec.mask             = {[fpath filesep 'brain_mask.nii']};
matlabbatch{1}.spm.stats.fmri_spec.cvi              = 'None'; 
matlabbatch{2}.spm.stats.fmri_est.spmmat(1)         = ...
    cfg_dep('fMRI model specification: SPM.mat File', substruct('.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','spmmat'));
matlabbatch{2}.spm.stats.fmri_est.write_residuals   = 1;
matlabbatch{2}.spm.stats.fmri_est.method.Classical  = 1;
residuals = spm_jobman('run',matlabbatch); clear matlabbatch;
VfMRI = spm_file_merge(residuals{2}.res,[fpath filesep 'clean_' fname '.nii']);
rmdir([fpath filesep 'regression'],'s')
clean_data = VfMRI.fname;



