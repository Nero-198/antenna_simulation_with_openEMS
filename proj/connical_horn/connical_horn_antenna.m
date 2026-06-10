close all
clear
clc


physical_constants;
unit = 1e-3; % すべての長さを mm 単位で扱う

%% sweep parameters

radius_list = [75];          % mm
length_list = [100 120 140 160 180 200];  % mm
angle_deg_list = [60 70 80 90];  % deg

feed_length = 200;           % mm
thickness = 2;               % mm

result_root = 'results_horn_sweep';

% 時系列電界ダンプは多数の .vtr を生成するため、通常のスイープでは無効。
% ParaViewで過渡電界を動画表示したいケースだけ true にする。
save_aperture_time_dump = false;

% PNG・MAT・集計値の生成後、巨大なNF2FF面データを削除する。
% falseなら、FDTDを再実行せずに別角度や3D遠方界を再計算できる。
delete_nf2ff_surface_h5_after_postprocessing = true;

% 再実行時は case_summary.mat がある完了済み条件を飛ばす。
skip_completed_cases = true;

if ~exist(result_root, 'dir')
    mkdir(result_root);
end

% 過去のケース結果を読み込み、今回のスイープ結果へ追記できるようにする。
summary = [];
existing_case_files = dir( ...
    fullfile(result_root, 'r*', 'case_summary.mat'));

for existing_index = 1:numel(existing_case_files)
    existing_data = load(fullfile( ...
        existing_case_files(existing_index).folder, ...
        existing_case_files(existing_index).name));

    if ~isfield(existing_data, 'case_result')
        continue;
    end

    existing_case = existing_data.case_result;
    existing_row = [ ...
        existing_case.radius_mm, ...
        existing_case.length_mm, ...
        existing_case.angle_deg, ...
        existing_case.aperture_radius_mm, ...
        existing_case.fc_te11_GHz, ...
        existing_case.fc_tm01_GHz, ...
        existing_case.Dmax_dBi, ...
        existing_case.aperture_efficiency_percent, ...
        existing_case.Eplane_beamwidth_10dB_deg, ...
        existing_case.Hplane_beamwidth_10dB_deg ...
    ];

    existing_key_index = [];
    if ~isempty(summary)
        existing_key_index = find(all( ...
            abs(summary(:, 1:3) - existing_row(1:3)) < 1e-9, 2), 1);
    end

    if isempty(existing_key_index)
        summary = [summary; existing_row];
    else
        summary(existing_key_index, :) = existing_row;
    end
end

if ~isempty(summary)
    summary = sortrows(summary, [1 2 3]);
end
fprintf('loaded %d existing sweep results\n', size(summary, 1));

case_index = 0;

for radius_i = 1:numel(radius_list)
for length_i = 1:numel(length_list)
for angle_i = 1:numel(angle_deg_list)

case_index = case_index + 1;

horn.radius = radius_list(radius_i);
horn.length = length_list(length_i);
horn.feed_length = feed_length;
horn.thickness = thickness;

angle_deg = angle_deg_list(angle_i);
horn.angle = angle_deg*pi/180;
horn.aperture_radius = horn.radius + sin(horn.angle)*horn.length;

case_name = sprintf('r%03.0f_L%03.0f_ang%03.0f', ...
    horn.radius, horn.length, angle_deg);

Sim_Path = fullfile(result_root, case_name);

if skip_completed_cases && ...
        exist(fullfile(Sim_Path, 'case_summary.mat'), 'file') == 2
    fprintf('skipping completed case %d: %s\n', case_index, case_name);
    continue;
end

fprintf('\n');
fprintf('========================================\n');
fprintf('case %d: %s\n', case_index, case_name);
fprintf('radius = %.1f mm\n', horn.radius);
fprintf('length = %.1f mm\n', horn.length);
fprintf('angle  = %.1f deg\n', angle_deg);
fprintf('aperture radius = %.1f mm\n', horn.aperture_radius);
fprintf('Sim_Path = %s\n', Sim_Path);
fprintf('========================================\n');

% 解析対象の周波数範囲
f_start =  1.2e9;
f_stop  =  1.50e9;
 
% 評価対象の中心周波数
f0 = 1420.405751768e6; % 水素原子の 21 cm 線の周波数

eh_plot_title = sprintf( ...
    'E-H Plane at %.3f MHz, horn_L=%.0f, ang=%.0f', ...
    f0/1e6, horn.length, angle_deg);

fc_te11 = 1.841*c0/(2*pi*horn.radius*unit);
fc_tm01 = 2.405*c0/(2*pi*horn.radius*unit);
fprintf('circular waveguide cutoff: TE11 = %.3f GHz, TM01 = %.3f GHz\n', ...
    fc_te11/1e9, fc_tm01/1e9);

if horn.angle == 0
    warning('horn.angle is zero: the model is an open circular waveguide, not a conical horn.');
end


% 励振ポートと基準面の z 座標
z_port_exc = -100;   % TE11 モードを入力する励振面
z_port_ref =  -50;   % 電圧・電流プローブ面、S11 の基準面
z_dump = 0;          % ホーン開始面
 
%% FDTD パラメータと励振関数の設定
FDTD = InitFDTD( 'NrTS', 30000, 'EndCriteria', 1e-4 );
FDTD = SetGaussExcite(FDTD,0.5*(f_start+f_stop),0.5*(f_stop-f_start));
pml_cells = 8;
pml_bc = sprintf('PML_%d', pml_cells);
BC = repmat({pml_bc}, 1, 6);
FDTD = SetBoundaryCond( FDTD, BC );



%% CSXCAD 形状とメッシュの設定  <--------------------------- ここが大事かも．
% 現在の openEMS ではメッシュを完全には自動生成できない
% 空気領域の波長基準。微細な金属形状は下の局所メッシュで解像する。
cells_per_wavelength = 20;
max_res = c0 / f_stop / unit / cells_per_wavelength;
CSX = InitCSX();

% 横方向境界をホーン開口、NF2FF余白、PMLの外側に自動配置する。
% SimBox(3)は従来どおり前方の +z 境界座標として使用する。
nf2ff_clearance = max_res;
outer_aperture_radius = horn.aperture_radius + horn.thickness;
xy_half_size = ceil( ...
    (outer_aperture_radius + nf2ff_clearance + ...
     pml_cells*max_res)/max_res)*max_res;
SimBox = [2*xy_half_size 2*xy_half_size 500];

fprintf('simulation x/y boundary: +/-%.1f mm\n', xy_half_size);
 
% PEC 厚さが1セルだけになると、円形壁の階段近似がメッシュごとに
% 大きく変わる。ホーンを含む領域では壁厚を最低2セルで表現する。
metal_cells = 2;
fine_xy_res = horn.thickness/metal_cells;

wall_radii = unique([ ...
    linspace(horn.radius, horn.radius + horn.thickness, 3), ...
    linspace(horn.aperture_radius, ...
             horn.aperture_radius + horn.thickness, 3) ...
]);

fine_xy_limit = ceil(max(wall_radii)/fine_xy_res)*fine_xy_res;
fine_xy_lines = (-fine_xy_limit:fine_xy_res:fine_xy_limit);

% 中央は対称な一様格子にする。開口半径の線を別途追加すると、開口角に
% よっては一様格子との間に極端に小さいセルができるため追加しない。
mesh.x = unique([ ...
    -SimBox(1)/2, fine_xy_lines, SimBox(1)/2 ...
]);
mesh.x = SmoothMeshLines( mesh.x, max_res, 1.4); % 指定した固定メッシュ線の間を滑らかなメッシュにする
 
mesh.y = mesh.x;
 
% シミュレーション領域と基板内部の分割に使う z 方向の固定メッシュ線を作成する
% z 方向の重要位置を固定メッシュ線として指定する
mesh.z = [ ...
    -horn.feed_length, ... % 管の後端
    z_port_exc, ...        % TE11 励振面: -100 mm
    z_port_ref, ...        % S11 基準面: -50 mm
    0:min(max_res, horn.length/20):horn.length, ... % ホーン部を軸方向に20分割以上
    SimBox(3) ...          % 解析領域の前方端
];

mesh.z = SmoothMeshLines(mesh.z, max_res, 1.4); % 指定した固定メッシュ線の間を滑らかなメッシュにする

fprintf('mesh: %d x %d x %d cells (%.3g million Yee cells)\n', ...
    numel(mesh.x)-1, numel(mesh.y)-1, numel(mesh.z)-1, ...
    (numel(mesh.x)-1)*(numel(mesh.y)-1)*(numel(mesh.z)-1)/1e6);
fprintf('cell width x/y: %.3f ... %.3f mm, z: %.3f ... %.3f mm\n', ...
    min(diff(mesh.x)), max(diff(mesh.x)), ...
    min(diff(mesh.z)), max(diff(mesh.z)));
%% z方向メッシュに重要位置が含まれているか確認

fprintf('z_port_exc = %.1f mm, contained in mesh: %d\n', ...
    z_port_exc, any(abs(mesh.z - z_port_exc) < 1e-9));

fprintf('z_port_ref = %.1f mm, contained in mesh: %d\n', ...
    z_port_ref, any(abs(mesh.z - z_port_ref) < 1e-9));

fprintf('z_dump     = %.1f mm, contained in mesh: %d\n', ...
    z_dump, any(abs(mesh.z - z_dump) < 1e-9));

fprintf('z_aperture = %.1f mm, contained in mesh: %d\n', ...
    horn.length, any(abs(mesh.z - horn.length) < 1e-9));


CSX = DefineRectGrid( CSX, unit, mesh );



%% ホーンの作成
% ホーンと導波管を、回転多角形として定義する
CSX = AddMetal(CSX, 'Conical_Horn');
p = [];  % sweep時に前回条件の点列が残らないようにする
p(1,1) = horn.radius+horn.thickness;   % 点 1 の x 座標
p(2,1) = -horn.feed_length;     % 点 1 の z 座標
p(1,end+1) = horn.radius+horn.thickness;   % 次の点の x 座標
p(2,end) = 0;     % 次の点の z 座標
p(1,end+1) = horn.radius+horn.thickness + sin(horn.angle)*horn.length; % 外側開口端の x 座標
p(2,end) = horn.length; % 外側開口端の z 座標
p(1,end+1) = horn.radius + sin(horn.angle)*horn.length; % 内側開口端の x 座標
p(2,end) = horn.length; % 内側開口端の z 座標
p(1,end+1) = horn.radius;  % 内側導波管端の x 座標
p(2,end) = 0;     % 内側導波管端の z 座標
p(1,end+1) = horn.radius;   % 給電導波管端の x 座標
p(2,end) = -horn.feed_length;     % 給電導波管端の z 座標
CSX = AddRotPoly(CSX,'Conical_Horn',10,'x',p,'z');
 
% ホーン開口面積
A = pi*(horn.aperture_radius*unit)^2;





%% 励振の適用 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 励振の適用：理想 TE11 モードポート


% TE11 モードを入力するための円形導波管ポートを定義する
start = [-horn.radius, -horn.radius, z_port_exc];
stop  = [ horn.radius,  horn.radius, z_port_ref];
[CSX, port] = AddCircWaveGuidePort( CSX, 0, 1, start, stop, horn.radius*unit, 'TE11', 0, 1);



%% 電磁界保存領域の設定とシミュレーション実行準備
%% ホーン開始面の時系列電界保存面

if save_aperture_time_dump
    CSX = AddDump(CSX, 'E_at_horn_throat', ...
                  'DumpType', 0, 'FileType', 0);
    start = [-horn.radius, -horn.radius, z_dump];
    stop  = [ horn.radius,  horn.radius, z_dump];
    CSX = AddBox(CSX, 'E_at_horn_throat', 0, start, stop);
end
 
%% nf2ff 計算領域の設定
% nf2ff 面を PML の内側境界に置く。PMLセル数を変更しても追従させる。
start = [ ...
    mesh.x(pml_cells+1), ...
    mesh.y(pml_cells+1), ...
    mesh.z(pml_cells+1) ...
];
stop = [ ...
    mesh.x(end-pml_cells), ...
    mesh.y(end-pml_cells), ...
    mesh.z(end-pml_cells) ...
];

assert(abs(start(1)) > horn.aperture_radius + horn.thickness);
assert(abs(start(2)) > horn.aperture_radius + horn.thickness);
assert(stop(3) > horn.length);

fprintf('nf2ff start = [%.1f %.1f %.1f] mm\n', start);
fprintf('nf2ff stop  = [%.1f %.1f %.1f] mm\n', stop);
% 遠方界は f0 だけで評価するため、時間波形ではなく周波数領域で保存する。
% これにより nf2ff_*.h5 の容量を大幅に削減できる。
[CSX nf2ff] = CreateNF2FFBox( ...
    CSX, 'nf2ff', start, stop, ...
    'Directions', [1 1 1 1 0 1], ...
    'Frequency', f0);
 
%% シミュレーション用フォルダの準備
%Sim_Path = 'tmp';
Sim_CSX = 'horn_ant.xml';
 
[status, message, messageid] = rmdir( Sim_Path, 's' ); % 以前の出力ディレクトリを削除する
[status, message, messageid] = mkdir( Sim_Path ); % 空のシミュレーションフォルダを作成する
 
%% openEMS 互換の XML ファイルを書き出す
WriteOpenEMS( [Sim_Path '/' Sim_CSX], FDTD, CSX );
 
%% 構造を表示する
show_AppCSXCAD = false; % openEMS 付属の AppCSXCAD で構造を表示するかどうか. スイープ毎に表示すると自動化できないので切る．
if show_AppCSXCAD
CSXGeomPlot( ...
    [Sim_Path '/' Sim_CSX], ...
    ['--export-polydata-vtk=' Sim_Path ' --RenderDiscMaterial -v'] ...
);
end

%% openEMS を実行する
num_threads = str2double(getenv('OPENEMS_NUM_THREADS'));
if ~isfinite(num_threads) || num_threads < 1 || num_threads ~= floor(num_threads)
    num_threads = 12;
end
openEMS_opts = sprintf( ...
    '--engine=multithreaded --numThreads=%d', num_threads);
fprintf('openEMS threads: %d\n', num_threads);
RunOpenEMS( Sim_Path, Sim_CSX, openEMS_opts);



%% 後処理とプロット
freq = linspace(f_start,f_stop,201);
 
port = calcPort(port, Sim_Path, freq);
 
Zin = port.uf.tot ./ port.if.tot;
s11 = port.uf.ref ./ port.uf.inc;
 
% 反射係数 S11 をプロットする
figure
plot( freq/1e9, 20*log10(abs(s11)), 'k-', 'Linewidth', 2 );
ylim([-60 0]);
grid on
title( 'reflection coefficient S_{11}' );
xlabel( 'frequency f / GHz' );
ylabel( 'reflection coefficient |S_{11}|' );
 
drawnow
 
%% NF2FF の等高線プロット %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
 
% phi=0 度および phi=90 度における遠方界を計算する
%% E面・H面の2断面遠方界

theta_cut = -180:2:180;

disp('calculating E-plane and H-plane far field cuts...');

nf2ff_cut = CalcNF2FF( ...
    nf2ff, Sim_Path, f0, ...
    theta_cut*pi/180, [0 90]*pi/180, ...
    'Outfile', 'nf2ff_EH_cut.h5', ...
    'Mode', 1);

%% アンテナパラメータ

Dlog = 10*log10(nf2ff_cut.Dmax);
G_a = 4*pi*A/(c0/f0)^2;
e_a = nf2ff_cut.Dmax/G_a;

disp(['radiated power: Prad = ' num2str(nf2ff_cut.Prad) ' Watt']);
disp(['directivity: Dmax = ' num2str(Dlog) ' dBi']);
disp(['aperture efficiency: e_a = ' num2str(e_a*100) '%']);

%% 絶対指向性 [dBi]

figure
plotFFdB(nf2ff_cut, 'xaxis', 'theta', 'param', [1 2]);
grid on;
title(sprintf('E-plane and H-plane directivity at %.3f MHz', f0/1e6));
drawnow

%% 極座標プロット

theta_deg = nf2ff_cut.theta * 180/pi;

% 正面半球（|theta| <= 90 deg）で最も強い方向を 0 dB とする。
E_abs = abs(nf2ff_cut.E_norm{1});
front_mask = abs(theta_deg) <= 90;
E_front = E_abs(front_mask, :);
[Efront_max, front_linear_index] = max(E_front(:));

front_theta = theta_deg(front_mask);
[front_theta_index, front_plane_index] = ind2sub( ...
    [numel(front_theta), size(E_abs, 2)], front_linear_index);

normalization_theta_deg = front_theta(front_theta_index);
normalization_phi_deg = nf2ff_cut.phi(front_plane_index)*180/pi;

fprintf('polar normalization: %.2f deg, phi = %.0f deg is 0 dB\n', ...
    normalization_theta_deg, normalization_phi_deg);

E_normalized = E_abs / Efront_max;
pattern_rel_dB = 20*log10(max(E_normalized, 10^(-60/20)));

Eplane_rel_dB = pattern_rel_dB(:,1);  % phi = 0 deg
Hplane_rel_dB = pattern_rel_dB(:,2);  % phi = 90 deg

% 正面主ローブの左右で最初に -10 dB を横切る角度を線形補間する。
cut_level_dB = -10;
front_pattern_dB = pattern_rel_dB(front_mask, :);
cut_angles_deg = nan(2, 2); % row: E/H, column: left/right
beamwidth_10dB_deg = nan(1, 2);


for plane_index = 1:2
    plane_front_dB = front_pattern_dB(:, plane_index);
    [~, peak_index] = max(plane_front_dB);

    left_index = find( ...
        plane_front_dB(1:peak_index) <= cut_level_dB, 1, 'last');
    if ~isempty(left_index) && left_index < peak_index
        cut_angles_deg(plane_index, 1) = interp1( ...
            plane_front_dB(left_index:left_index+1), ...
            front_theta(left_index:left_index+1), ...
            cut_level_dB);
    end

    right_offset = find( ...
        plane_front_dB(peak_index:end) <= cut_level_dB, 1, 'first');
    if ~isempty(right_offset) && right_offset > 1
        right_index = peak_index + right_offset - 1;
        cut_angles_deg(plane_index, 2) = interp1( ...
            plane_front_dB(right_index-1:right_index), ...
            front_theta(right_index-1:right_index), ...
            cut_level_dB);
    end

    if all(isfinite(cut_angles_deg(plane_index, :)))
        beamwidth_10dB_deg(plane_index) = ...
            diff(cut_angles_deg(plane_index, :));
    end
end

fprintf('E-plane -10 dB: %.2f deg, %.2f deg (width %.2f deg)\n', ...
    cut_angles_deg(1, 1), cut_angles_deg(1, 2), beamwidth_10dB_deg(1));
fprintf('H-plane -10 dB: %.2f deg, %.2f deg (width %.2f deg)\n', ...
    cut_angles_deg(2, 1), cut_angles_deg(2, 2), beamwidth_10dB_deg(2));

case_result.radius_mm = horn.radius;
case_result.length_mm = horn.length;
case_result.feed_length_mm = horn.feed_length;
case_result.thickness_mm = horn.thickness;
case_result.angle_deg = angle_deg;
case_result.aperture_radius_mm = horn.aperture_radius;

case_result.fc_te11_GHz = fc_te11/1e9;
case_result.fc_tm01_GHz = fc_tm01/1e9;

case_result.Dmax_dBi = Dlog;
case_result.aperture_efficiency_percent = e_a*100;

case_result.Eplane_left_10dB_deg = cut_angles_deg(1, 1);
case_result.Eplane_right_10dB_deg = cut_angles_deg(1, 2);
case_result.Eplane_beamwidth_10dB_deg = beamwidth_10dB_deg(1);

case_result.Hplane_left_10dB_deg = cut_angles_deg(2, 1);
case_result.Hplane_right_10dB_deg = cut_angles_deg(2, 2);
case_result.Hplane_beamwidth_10dB_deg = beamwidth_10dB_deg(2);

save(fullfile(Sim_Path, 'case_summary.mat'), 'case_result');

save(fullfile(Sim_Path, 'EH_pattern.mat'), ...
     'theta_deg', 'Eplane_rel_dB', 'Hplane_rel_dB', ...
     'Efront_max', 'normalization_theta_deg', 'normalization_phi_deg', ...
     'cut_level_dB', 'cut_angles_deg', 'beamwidth_10dB_deg');

new_summary_row = [ ...
    horn.radius, ...
    horn.length, ...
    angle_deg, ...
    horn.aperture_radius, ...
    fc_te11/1e9, ...
    fc_tm01/1e9, ...
    Dlog, ...
    e_a*100, ...
    beamwidth_10dB_deg(1), ...
    beamwidth_10dB_deg(2) ...
];

% 同じ半径・長さ・角度は重複追加せず、最新結果で置き換える。
summary_key_index = [];
if ~isempty(summary)
    summary_key_index = find(all( ...
        abs(summary(:, 1:3) - new_summary_row(1:3)) < 1e-9, 2), 1);
end

if isempty(summary_key_index)
    summary = [summary; new_summary_row];
else
    summary(summary_key_index, :) = new_summary_row;
end

summary = sortrows(summary, [1 2 3]);

% スイープが途中で停止しても結果が残るよう、ケースごとに集計を更新する。
summary_csv = fullfile(result_root, 'summary.csv');
fid = fopen(summary_csv, 'w');

fprintf(fid, ['radius_mm,length_mm,angle_deg,aperture_radius_mm,' ...
              'fc_te11_GHz,fc_tm01_GHz,Dmax_dBi,' ...
              'aperture_efficiency_percent,' ...
              'Eplane_beamwidth_10dB_deg,Hplane_beamwidth_10dB_deg\n']);

for summary_index = 1:size(summary, 1)
    fprintf(fid, ...
        '%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g\n', ...
        summary(summary_index, :));
end

fclose(fid);
save(fullfile(result_root, 'summary.mat'), 'summary');
fprintf('partial summary updated: %s (%d cases)\n', ...
    summary_csv, size(summary, 1));

% polarFF に正規化済みデータと Dmax=1 を渡すことで、半径を -40...0 dB
% の相対値として表示する。
nf2ff_polar = nf2ff_cut;
% polarFF は入力全体を再正規化するため、0 dBを超える背面成分は表示上
% 0 dBに制限し、正面基準を維持する。数値データには制限前の値を保存する。
nf2ff_polar.E_norm{1} = min(E_normalized, 1);
nf2ff_polar.Dmax = 1;

fig_polar = figure( ...
    'Color', 'white', 'Position', [100 100 1100 800]);
polar_pattern = polarFF( ...
    nf2ff_polar, 'xaxis', 'theta', 'param', [1 2], ...
    'logscale', [-40 0], 'xtics', 8);
title(eh_plot_title, 'Interpreter', 'none');

% polarFFでは -40 dBが半径0、0 dBが半径1に対応する。
polar_min_dB = -40;
cut_radius = (cut_level_dB - polar_min_dB)/(0 - polar_min_dB);
circle_angle = linspace(0, 2*pi, 361);
hold on;
plot(cut_radius*cos(circle_angle), cut_radius*sin(circle_angle), ...
     'k--', 'LineWidth', 1);

for plane_index = 1:2
    plane_color = get(polar_pattern(plane_index), 'Color');
    for side_index = 1:2
        cut_angle = cut_angles_deg(plane_index, side_index);
        if ~isfinite(cut_angle)
            continue;
        end

        cut_angle_rad = cut_angle*pi/180;
        plot([0 cos(cut_angle_rad)], [0 sin(cut_angle_rad)], ...
             '--', 'Color', plane_color, 'LineWidth', 1.2);
        plot(cut_radius*cos(cut_angle_rad), ...
             cut_radius*sin(cut_angle_rad), ...
             'o', 'Color', plane_color, ...
             'MarkerFaceColor', plane_color, 'MarkerSize', 5);

        label_radius = 0.82 + 0.10*(plane_index-1);
        text(label_radius*cos(cut_angle_rad), ...
             label_radius*sin(cut_angle_rad), ...
             sprintf('%.1f deg', cut_angle), ...
             'Color', plane_color, ...
             'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'middle');
    end
end

text(cut_radius*cos(75*pi/180), cut_radius*sin(75*pi/180), ...
     '-10 dB', 'HorizontalAlignment', 'center');
hold off;

legend(polar_pattern, ...
       {'E-plane: \phi = 0 deg', 'H-plane: \phi = 90 deg'}, ...
       'Location', 'southoutside');
drawnow;

polar_png = fullfile(Sim_Path, 'EH_pattern_polar_relative_dB.png');
set(fig_polar, 'PaperPositionMode', 'auto');
print(fig_polar, polar_png, '-dpng', '-r300');
fprintf('saved polar E/H pattern: %s\n', polar_png);

%% E面・H面の最大値基準相対パターン

fig_cartesian = figure( ...
    'Color', 'white', 'Position', [100 100 1100 800]);
plot(theta_deg, Eplane_rel_dB, 'LineWidth', 2);
hold on;
plot(theta_deg, Hplane_rel_dB, 'LineWidth', 2);
set(gca, 'Position', [0.10 0.12 0.80 0.70]);

grid on;
xlim([-90 90]);
ylim([-40 0]);
xlabel('\theta / deg');
ylabel('Relative level / dB');
legend('E-plane: \phi = 0 deg', 'H-plane: \phi = 90 deg');
title(eh_plot_title, 'Interpreter', 'none');
drawnow;

cartesian_png = fullfile(Sim_Path, 'EH_pattern_cartesian_relative_dB.png');
set(fig_cartesian, 'PaperPositionMode', 'auto');
print(fig_cartesian, cartesian_png, '-dpng', '-r300');
fprintf('saved Cartesian E/H pattern: %s\n', cartesian_png);

%% 3D 放射パターンの計算
do_3d = false; % 3D パターンの計算は時間がかかるため、必要な場合にのみ実行する

if do_3d

phiRange = sort(unique([ ...
    -180:5:-100, -100:2.5:-50, -50:1:50, ...
     50:2.5:100, 100:5:180 ]));

thetaRange = sort(unique([0:1:50, 50:2:100, 100:5:180]));

disp('calculating 3D far field...');

nf2ff_3D = CalcNF2FF( ...
    nf2ff, Sim_Path, f0, ...
    thetaRange*pi/180, phiRange*pi/180, ...
    'Verbose', 2, ...
    'Outfile', 'nf2ff_3D.h5', ...
    'Mode', 1);

figure
plotFF3D(nf2ff_3D);

E_far_normalized = nf2ff_3D.E_norm{1} / max(nf2ff_3D.E_norm{1}(:));

DumpFF2VTK( ...
    [Sim_Path '/Conical_Horn_Pattern.vtk'], ...
    E_far_normalized, thetaRange, phiRange, 'scale', 1e-1);

end %do_3d

if delete_nf2ff_surface_h5_after_postprocessing
    nf2ff_surface_files = [ ...
        dir(fullfile(Sim_Path, 'nf2ff_E_*.h5')); ...
        dir(fullfile(Sim_Path, 'nf2ff_H_*.h5')) ...
    ];

    deleted_bytes = 0;
    for file_index = 1:numel(nf2ff_surface_files)
        deleted_bytes = deleted_bytes + nf2ff_surface_files(file_index).bytes;
        delete(fullfile( ...
            Sim_Path, nf2ff_surface_files(file_index).name));
    end

    fprintf('deleted %d NF2FF surface files (%.3f GiB): %s\n', ...
        numel(nf2ff_surface_files), deleted_bytes/1024^3, Sim_Path);
end

close all;

end
end
end

%% save sweep summary

summary_csv = fullfile(result_root, 'summary.csv');

fprintf('\nSweep finished.\n');
fprintf('summary saved: %s\n', summary_csv);
