close all
clear
clc

result_root = 'results_horn_sweep';
case_files = dir(fullfile(result_root, 'r*', 'case_summary.mat'));
summary = [];

for case_index = 1:numel(case_files)
    case_data = load(fullfile(case_files(case_index).folder, case_files(case_index).name));
    if ~isfield(case_data, 'case_result')
        continue;
    end

    result = case_data.case_result;
    summary = [summary; ...
        result.radius_mm, ...
        result.length_mm, ...
        result.angle_deg, ...
        result.aperture_radius_mm, ...
        result.fc_te11_GHz, ...
        result.fc_tm01_GHz, ...
        result.Dmax_dBi, ...
        result.aperture_efficiency_percent, ...
        result.Eplane_beamwidth_10dB_deg, ...
        result.Hplane_beamwidth_10dB_deg ...
    ];
end

if isempty(summary)
    error('No completed cases found below %s', result_root);
end

summary = sortrows(summary, [1 2 3]);
header = [ ...
    'radius_mm,length_mm,angle_deg,aperture_radius_mm,' ...
    'fc_te11_GHz,fc_tm01_GHz,Dmax_dBi,' ...
    'aperture_efficiency_percent,' ...
    'Eplane_beamwidth_10dB_deg,Hplane_beamwidth_10dB_deg' ...
];

summary_csv = fullfile(result_root, 'summary.csv');
fid = fopen(summary_csv, 'w');
assert(fid >= 0, 'Could not open %s', summary_csv);
fprintf(fid, '%s\n', header);
for row_index = 1:size(summary, 1)
    fprintf(fid, '%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g\n', ...
        summary(row_index, :));
end
fclose(fid);
save(fullfile(result_root, 'summary.mat'), 'summary');

ranking = sortrows(summary, -7);
ranking_csv = fullfile(result_root, 'ranking_by_Dmax.csv');
fid = fopen(ranking_csv, 'w');
assert(fid >= 0, 'Could not open %s', ranking_csv);
fprintf(fid, '%s\n', header);
for row_index = 1:size(ranking, 1)
    fprintf(fid, '%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g\n', ...
        ranking(row_index, :));
end
fclose(fid);

fprintf('rebuilt summary from %d completed cases: %s\n', ...
    size(summary, 1), summary_csv);
fprintf('best Dmax: L=%.1f mm, angle=%.1f deg, Dmax=%.4f dBi\n', ...
    ranking(1, 2), ranking(1, 3), ranking(1, 7));
