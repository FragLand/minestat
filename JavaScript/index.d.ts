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

  interface InitFn {
    (address: string, port: number, callback: Callback): void;
    (address: string, port: number, timeout: number, callback: Callback): void;
  }

  interface MineStat {
    VERSION: string;
    init: InitFn;
  }

  const minestat: MineStat;

  export = minestat;
}
