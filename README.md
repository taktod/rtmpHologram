# rtmpHologramプログラム

## 作者 taktod

## ライセンス
MITライセンスとしておきます。

## 内容
スマホとちょっとした工作で作ることができる簡易ホログラム用のデータを作るプログラム
参考：https://www.youtube.com/watch?v=XHNWHPuXJag
こういうやつです。
作成するデータは４つのミラーになっている画像っぽいのを作ります。
参考：https://www.youtube.com/watch?v=LXHy8JCe0oA

## 大まかな動作
1. Macのカメラで画像取得
2. openGLで画像を加工
3. 適当にh264とaacのデータにする
4. rtmpでデータを送る
5. スマホでVLCあたり使って再生して、ホログラム出来上がり。

## 必要なもの。
* Mac
* Xcode
* red5サーバー
* ttLibC https://github.com/taktod/ttLibC/ developブランチ使います

## 下準備
ttLibC入手する。
$ git clone https://github.com/taktod/ttLibC.git
$ git checkout develop
$ autoreconf
$ ./configure —enable-apple
$ make
$ sudo make install

red5を準備する
https://github.com/Red5/red5-server/releases
ここで1.0.7入手しました。
tar.gzのsourceをゲット
$ mvn compile
$ mvn -Dmaven.test.skip=true clean package -P assemble
を実行して、サーバープログラムを作成。
適当に配信と視聴ができることを確認しました。

プログラムを作っていたところ、red5-1.0.7を利用するとttLibCのrtmp接続が拒否されることがわかりました。
とりあえず1.0.4にバージョンダウンして再チャレンジです。
(この接続バグは後で直そうかなと思います。)

https://github.com/Red5/red5-server/releases
から1.0.4Releaseを取得今回はsourceではなく、普通のtar.gzを取得しました。
$ tar zxvf red5-server-1.0.4-RELEASE-server.tar.gz
$ cd red5-server-1.0.4-RELEASE/
$ ./red5.sh
で実行できました。
