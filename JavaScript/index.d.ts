declare module 'minestat' {

  type BaseStats<T, U> = {
    address: T;
    port: U;
    latency: number;
  };

  type Online<T, U> = BaseStats<T, U> & {
    online: true;
    version: string;
    max_players: number;
    current_players: number;
    motd: string;
  };

  type Offline<T, U> = BaseStats<T, U> & {
    online: false;
  };

  type Stats<T, U> = Readonly<Online<T, U> | Offline<T, U>>;

  interface Callback<T, U> {
    (error: Error): void;
    (error: never, result: Stats<T, U>): void;
  }

  interface InitFn {
    (address: string, port: number, callback: Callback<typeof address, typeof port>): void;
    (address: string, port: number, timeout: number, callback: Callback<typeof address, typeof port>): void;
  }

  interface MineStat {
    VERSION: string;
    init: InitFn;
  }

  const minestat: MineStat;

  export = minestat;
}
