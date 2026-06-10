import os, tempfile
from pylab import *
from CSXCAD  import ContinuousStructure
from openEMS import openEMS
from openEMS.physical_constants import *

# シミュレーション結果を保存するディレクトリを一時フォルダ内に作成する。
# tempfile.gettempdir() は OS が使う一時ディレクトリを返す。
Sim_Path = os.path.join(tempfile.gettempdir(), 'Rect_WG')

# True にすると FDTD 計算を再実行せず、既存の結果ファイルから後処理だけを行う。
post_proc_only = False

# openEMS/CSXCAD で使う座標の単位を指定する。
# ここでは 1 座標単位 = 1 um = 1e-6 m としている。
unit  = 1e-6;   # unit in um

# 導波管の寸法パラメータ。
# WR42 は K バンド付近で使われる標準的な矩形導波管サイズ。
a = 10700;
b = 4300;
length = 50000;

# 解析する周波数範囲。
f_start = 20e9;
f_0 = 24e9;
f_stop  = 26e9;

# 中心周波数 f_0 における自由空間波長を、メッシュ座標単位に変換する。
# C0 は openEMS.physical_constants で定義される真空中の光速 [m/s]。
# unit で割ることで m から um ベースの座標単位に直している。
lambda0 = C0/f_0/unit;

# 矩形導波管で励振する TE モードを指定する。
# TE10 は矩形導波管の基本モードで、通常最も低いカットオフ周波数を持つ。
TE_mode = "TE10";

# 目標メッシュ解像度。
# 波長を 30 分割する程度のセルサイズを目安にしている。
mesh_res = lambda0/30;

# openEMS の FDTD ソルバを作成する。
# NrTS は最大タイムステップ数で、ここでは 1e4 ステップまで計算する。
FDTD = openEMS(NrTS = 1e4);

# ガウス型の広帯域励振を設定する。
# 第 1 引数は中心周波数、第 2 引数は帯域幅を表す。
FDTD.SetGaussExcite(0.5*(f_stop+f_start), 0.5*(f_stop-f_start) );

# 境界条件を x-, x+, y-, y+, z-, z+ の順に指定する。
# 0 は完全導体境界、3 は PML 吸収境界を表す。
# ここでは z 方向の両端だけを PML にして、導波管の入出力方向で反射を抑える。
FDTD.SetBoundaryCond([0,0,0,0,3,3]) # PML for z direction;

# CSXCAD の連続構造オブジェクトを作成し、FDTD ソルバに接続する。
# 形状、材料、メッシュ、ダンプ領域などはこの CSX に登録される。
CSX = ContinuousStructure()
FDTD.SetCSX(CSX)

# 計算格子オブジェクトを取得し、座標単位を um に設定する。
mesh = CSX.GetGrid()
mesh.SetDeltaUnit(unit)

# 導波管外形の端点にメッシュ線を追加する。
# これにより x=0,a、y=0,b、z=0,length の位置が格子に含まれる。
mesh.AddLine('x', [0,a])
mesh.AddLine('y', [0,b])
mesh.AddLine('z', [0,length])

# 導波管ポートを格納するリスト。
# ports[0] が入力側、ports[1] が出力側として後で使われる。
ports = []

# 入力ポートの領域を定義する。
# start/stop は直方体領域の対角点で、z=10*mesh_res から 15*mesh_res の薄い領域をポートにする。
start=[0, 0, 10*mesh_res];
stop =[a, b, 15*mesh_res];

# ポート位置の z 座標をメッシュ線として追加し、ポート境界が格子に一致するようにする。
mesh.AddLine('z', [start[2], stop[2]])

# 入力側の矩形導波管ポートを追加する。
# 引数の 0 はポート番号、'z' は伝搬方向、a*unit/b*unit は実寸 [m]。
# 最後の 1 はこのポートを励振源として有効にする指定。
ports.append(FDTD.AddRectWaveGuidePort( 0, start, stop, 'z', a*unit, b*unit, TE_mode, 1))

# 出力ポートの領域を導波管の終端側に定義する。
# z 座標を length から少し手前に置き、PML 境界から離している。
start=[0, 0, length-10*mesh_res];
stop =[a, b, length-15*mesh_res];

# 出力ポート位置もメッシュ線として明示的に追加する。
mesh.AddLine('z', [start[2], stop[2]])

# 出力側の矩形導波管ポートを追加する。
# 励振フラグを指定していないため、ここは観測用ポートとして使われる。
ports.append(FDTD.AddRectWaveGuidePort( 1, start, stop, 'z', a*unit, b*unit, TE_mode))

# 全方向のメッシュを滑らかにする。
# mesh_res を目標セル幅とし、隣接セル幅の増加比を 1.4 以下に抑える。
mesh.SmoothMeshLines('all', mesh_res, ratio=1.4)

# 電界分布を保存するダンプ領域を追加する。
# file_type=0 は time-domain dump、sub_sampling=[2,2,2] は各方向 2 セルおきに間引いて保存する指定。
Et = CSX.AddDump('Et', file_type=0, sub_sampling=[2,2,2])

# 電界を保存する範囲を導波管全体に設定する。
start = [0, 0, 0];
stop  = [a, b, length];
Et.AddBox(start, stop);

# デバッグ用ブロック。
# if 0 なので通常は実行されない。1 に変更すると CSX 形状を XML に出力して AppCSXCAD で確認できる。
if 0:  # debugging only
    # 形状確認用 XML ファイルの保存先を決める。
    CSX_file = os.path.join(Sim_Path, 'rect_wg.xml')

    # 出力ディレクトリが存在しない場合だけ作成する。
    if not os.path.exists(Sim_Path):
        os.mkdir(Sim_Path)

    # CSXCAD の形状・メッシュ情報を XML ファイルとして書き出す。
    CSX.Write2XML(CSX_file)

    # AppCSXCAD の実行ファイル名を取得し、書き出した XML を GUI で開く。
    from CSXCAD import AppCSXCAD_BIN
    os.system(AppCSXCAD_BIN + ' "{}"'.format(CSX_file))

# post_proc_only が False の場合、FDTD シミュレーション本体を実行する。
if not post_proc_only:
    # Sim_Path に結果を出力する。cleanup=True により古い結果ファイルを消してから実行する。
    FDTD.Run(Sim_Path, cleanup=True)

    # 後処理で評価する周波数点を作成する。
    # 20 GHz から 26 GHz までを 201 点に分割している。
    freq = linspace(f_start,f_stop,201)

# 各ポートについて、保存された時間波形から周波数領域の入射波・反射波などを計算する。
for port in ports:
    port.CalcPort(Sim_Path, freq)

# 入力ポートの反射係数 S11。
# uf_ref は反射波電圧、uf_inc は入射波電圧を表す。
s11 = ports[0].uf_ref / ports[0].uf_inc

# 伝達係数 S21。
# 出力ポート側で得られた波を入力ポートの入射波で正規化している。
s21 = ports[1].uf_ref / ports[0].uf_inc

# 入力ポートから見た負荷インピーダンス。
# uf_tot は全電圧、if_tot は全電流。
ZL  = ports[0].uf_tot / ports[0].if_tot

# openEMS がモード解析から計算した解析的な導波管インピーダンス。
ZL_a = ports[0].ZL # analytic waveguide impedance

# S パラメータを dB 表示でプロットする図を作成する。
figure()

# S11 を黒実線で描画する。abs(s11) を dB に変換している。
plot(freq*1e-6,20*log10(abs(s11)),'k-',linewidth=2, label='$S_{11}$')

# グリッドを表示し、読み取りやすくする。
grid()

# S21 を赤破線で同じ図に描画する。
plot(freq*1e-6,20*log10(abs(s21)),'r--',linewidth=2, label='$S_{21}$')

# 凡例と軸ラベルを設定する。
legend();
ylabel('S-Parameter (dB)')
xlabel(r'frequency (MHz) $\rightarrow$')

# 導波管インピーダンスを表示する別の図を作成する。
figure()

# 数値計算で得た入力インピーダンスの実部を描画する。
plot(freq*1e-6,real(ZL), linewidth=2, label=r'$\Re\{Z_L\}$')
grid()

# 数値計算で得た入力インピーダンスの虚部を赤破線で描画する。
plot(freq*1e-6,imag(ZL),'r--', linewidth=2, label=r'$\Im\{Z_L\}$')

# 解析式から求めた導波管インピーダンスを緑の一点鎖線で描画し、数値結果と比較する。
plot(freq*1e-6,ZL_a,'g-.',linewidth=2, label='$Z_{L, analytic}$')

# 凡例と軸ラベルを設定する。
ylabel(r'ZL $(\Omega)$')
xlabel(r'frequency (MHz) $\rightarrow$')
legend()

# 作成した matplotlib の図を画面に表示する。
show()
