declare module 'minestat' {

  type BaseStats = {
    address: string;
    port: number;
    latency: number;
  };

  type Online = BaseStats & {
    online: true;
    version: string;
    max_players: number;
    current_players: number;
    motd: string;
  };

  type Offline = BaseStats & {
    online: false;
  };

  type Stats = Readonly<Online | Offline>;

  interface Callback {
    (error: Error): void;
    (error: never, result: Stats): void;
  }

  interface Options {
    address: string;
    port: number;
    timeout?: number;
  }

  type InitFn = (options: Options, callback: Callback) => void;
  type AsyncInit = (options: Options) => Promise<Stats>;

  interface MineStat {
    VERSION: string;
    init: AsyncInit;
    initSync: InitFn;
  }

  const minestat: MineStat;

  export = minestat;
}
