import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The operating system's SQLite, bound through dart:ffi alone: Apple's
/// /usr/lib/libsqlite3.dylib on iOS and macOS (in the dyld shared cache, built
/// with the authorizer and progress handler and without extension loading),
/// and the distribution's libsqlite3.so.0 where `flutter test` runs on Linux
/// CI. Only what [JournalDb] uses is bound.
final class Sqlite {
  Sqlite._(DynamicLibrary lib)
    : openV2 = lib
          .lookupFunction<
            Int Function(
              Pointer<Utf8>,
              Pointer<Pointer<Void>>,
              Int,
              Pointer<Utf8>,
            ),
            int Function(
              Pointer<Utf8>,
              Pointer<Pointer<Void>>,
              int,
              Pointer<Utf8>,
            )
          >('sqlite3_open_v2'),
      closeV2 = lib
          .lookupFunction<
            Int Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_close_v2'),
      errmsg = lib
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)
          >('sqlite3_errmsg'),
      exec = lib
          .lookupFunction<
            Int Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Utf8>>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Utf8>>,
            )
          >('sqlite3_exec'),
      prepareV3 = lib
          .lookupFunction<
            Int Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Int,
              UnsignedInt,
              Pointer<Pointer<Void>>,
              Pointer<Pointer<Utf8>>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Utf8>,
              int,
              int,
              Pointer<Pointer<Void>>,
              Pointer<Pointer<Utf8>>,
            )
          >('sqlite3_prepare_v3'),
      step = lib
          .lookupFunction<
            Int Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_step'),
      reset = lib
          .lookupFunction<
            Int Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_reset'),
      finalize = lib
          .lookupFunction<
            Int Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_finalize'),
      stmtReadonly = lib
          .lookupFunction<
            Int Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_stmt_readonly'),
      stmtIsExplain = lib
          .lookupFunction<
            Int Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_stmt_isexplain'),
      columnCount = lib
          .lookupFunction<
            Int Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_column_count'),
      columnName = lib
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Int),
            Pointer<Utf8> Function(Pointer<Void>, int)
          >('sqlite3_column_name'),
      columnType = lib
          .lookupFunction<
            Int Function(Pointer<Void>, Int),
            int Function(Pointer<Void>, int)
          >('sqlite3_column_type'),
      columnInt64 = lib
          .lookupFunction<
            Int64 Function(Pointer<Void>, Int),
            int Function(Pointer<Void>, int)
          >('sqlite3_column_int64'),
      columnDouble = lib
          .lookupFunction<
            Double Function(Pointer<Void>, Int),
            double Function(Pointer<Void>, int)
          >('sqlite3_column_double'),
      columnText = lib
          .lookupFunction<
            Pointer<Uint8> Function(Pointer<Void>, Int),
            Pointer<Uint8> Function(Pointer<Void>, int)
          >('sqlite3_column_text'),
      columnBytes = lib
          .lookupFunction<
            Int Function(Pointer<Void>, Int),
            int Function(Pointer<Void>, int)
          >('sqlite3_column_bytes'),
      bindInt64 = lib
          .lookupFunction<
            Int Function(Pointer<Void>, Int, Int64),
            int Function(Pointer<Void>, int, int)
          >('sqlite3_bind_int64'),
      bindDouble = lib
          .lookupFunction<
            Int Function(Pointer<Void>, Int, Double),
            int Function(Pointer<Void>, int, double)
          >('sqlite3_bind_double'),
      bindText = lib
          .lookupFunction<
            Int Function(Pointer<Void>, Int, Pointer<Utf8>, Int, Pointer<Void>),
            int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Void>)
          >('sqlite3_bind_text'),
      bindNull = lib
          .lookupFunction<
            Int Function(Pointer<Void>, Int),
            int Function(Pointer<Void>, int)
          >('sqlite3_bind_null'),
      setAuthorizer = lib
          .lookupFunction<
            Int Function(
              Pointer<Void>,
              Pointer<NativeFunction<AuthorizerNative>>,
              Pointer<Void>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<NativeFunction<AuthorizerNative>>,
              Pointer<Void>,
            )
          >('sqlite3_set_authorizer'),
      progressHandler = lib
          .lookupFunction<
            Void Function(
              Pointer<Void>,
              Int,
              Pointer<NativeFunction<ProgressNative>>,
              Pointer<Void>,
            ),
            void Function(
              Pointer<Void>,
              int,
              Pointer<NativeFunction<ProgressNative>>,
              Pointer<Void>,
            )
          >('sqlite3_progress_handler'),
      limit = lib
          .lookupFunction<
            Int Function(Pointer<Void>, Int, Int),
            int Function(Pointer<Void>, int, int)
          >('sqlite3_limit'),
      dbConfig = lib
          .lookupFunction<
            Int Function(Pointer<Void>, Int, VarArgs<(Int, Pointer<Int>)>),
            int Function(Pointer<Void>, int, int, Pointer<Int>)
          >('sqlite3_db_config');

  static Sqlite? _instance;

  /// The system library, opened once per isolate.
  static Sqlite get instance => _instance ??= Sqlite._(
    DynamicLibrary.open(
      Platform.isIOS || Platform.isMacOS
          ? '/usr/lib/libsqlite3.dylib'
          : 'libsqlite3.so.0',
    ),
  );

  final int Function(Pointer<Utf8>, Pointer<Pointer<Void>>, int, Pointer<Utf8>)
  openV2;
  final int Function(Pointer<Void>) closeV2;
  final Pointer<Utf8> Function(Pointer<Void>) errmsg;
  final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Pointer<Utf8>>,
  )
  exec;
  final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    int,
    int,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Utf8>>,
  )
  prepareV3;
  final int Function(Pointer<Void>) step;
  final int Function(Pointer<Void>) reset;
  final int Function(Pointer<Void>) finalize;
  final int Function(Pointer<Void>) stmtReadonly;
  final int Function(Pointer<Void>) stmtIsExplain;
  final int Function(Pointer<Void>) columnCount;
  final Pointer<Utf8> Function(Pointer<Void>, int) columnName;
  final int Function(Pointer<Void>, int) columnType;
  final int Function(Pointer<Void>, int) columnInt64;
  final double Function(Pointer<Void>, int) columnDouble;
  final Pointer<Uint8> Function(Pointer<Void>, int) columnText;
  final int Function(Pointer<Void>, int) columnBytes;
  final int Function(Pointer<Void>, int, int) bindInt64;
  final int Function(Pointer<Void>, int, double) bindDouble;
  final int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Void>)
  bindText;
  final int Function(Pointer<Void>, int) bindNull;
  final int Function(
    Pointer<Void>,
    Pointer<NativeFunction<AuthorizerNative>>,
    Pointer<Void>,
  )
  setAuthorizer;
  final void Function(
    Pointer<Void>,
    int,
    Pointer<NativeFunction<ProgressNative>>,
    Pointer<Void>,
  )
  progressHandler;
  final int Function(Pointer<Void>, int, int) limit;
  final int Function(Pointer<Void>, int, int, Pointer<Int>) dbConfig;
}

typedef AuthorizerNative = Int Function(
  Pointer<Void>,
  Int,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef ProgressNative = Int Function(Pointer<Void>);

/// Result and option codes from sqlite3.h.
abstract final class Sq {
  static const int ok = 0;
  static const int error = 1;
  static const int interrupt = 9;
  static const int tooBig = 18;
  static const int auth = 23;
  static const int row = 100;
  static const int done = 101;

  static const int integer = 1;
  static const int float = 2;
  static const int text = 3;
  static const int blob = 4;
  static const int nullType = 5;

  static const int openReadWrite = 0x02;
  static const int openCreate = 0x04;
  static const int openMemory = 0x80;
  static const int openNoMutex = 0x8000;
  static const int openPrivateCache = 0x40000;
  static const int openNoFollow = 0x01000000;

  static const int prepareNoVtab = 0x04;

  static const int authDeny = 1;

  static const int actionRead = 20;
  static const int actionSelect = 21;
  static const int actionFunction = 31;
  static const int actionRecursive = 33;

  static const int limitLength = 0;
  static const int limitSqlLength = 1;
  static const int limitColumn = 2;
  static const int limitExprDepth = 3;
  static const int limitCompoundSelect = 4;
  static const int limitFunctionArg = 6;
  static const int limitAttached = 7;
  static const int limitLikePatternLength = 8;
  static const int limitVariableNumber = 9;
  static const int limitTriggerDepth = 10;

  static const int configEnableTrigger = 1003;
  static const int configEnableLoadExtension = 1005;
  static const int configDefensive = 1010;
  static const int configWritableSchema = 1011;
  static const int configEnableView = 1015;
  static const int configTrustedSchema = 1017;
}

/// SQLITE_TRANSIENT: SQLite copies a bound text before the call returns.
final Pointer<Void> sqliteTransient = Pointer<Void>.fromAddress(-1);
