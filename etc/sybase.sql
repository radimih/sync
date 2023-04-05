######################################################################
# Autor: Радимир Михайлов (radimir@mobilcard.ru)
# Descr: Вспомогательный файл для работы с СУБД
# -------------------------------------------------------------------
# $Id $
# -------------------------------------------------------------------
# В файле определяются переменные для работы с БД, все используемые
# в системе SQL-выражения и функция получения результата выборки.
#
# Примечание:
#
#   Файл должен встраиваться в скрипт после определения всех
#   общих и индивидуальных параметров узла.
#
# Sybase SQL Anywhere
# -------------------
#
# SQL-выражения, которые возвращают какие-либо значения должны
# заканчиваться соответствующим select-ом без разделителя
# операторов в конце. В данном случае используется особенность
# СУБД, позволяющее перенаправлять результат выборки в файл
# (см. функцию sql_valuelist).
#
######################################################################

# ********************************************************************
# Общие переменные

SQL_UPPER=ucase          # Имя функции sql, переводящей строку-аргумент
                         # в заглавные буквы

SQL_SYSFIELD1=Packet     # Служебные поля, добавляемые в каждую
SQL_SYSFIELD2=InitPacket # синхронизируемую таблицу:
                         #   Packet     - номер пакета
                         #   InitPacket - номер начального пакета

SQL_FIELD_IN_PKEY=Y      # Признак вхождения поля в первичный ключ
                         # в метаданных СУБД

SQL_CURSORNAME="cur_<owner>_<table>" # Имя курсора, используемое при
                                     # обновлении данных.
                                     # Sybase требует уникальности
                                     # данного идентификатора в
                                     # пределах скрипта.

SQL_FIELDPREFIX1=cur_                #
SQL_FIELDPREFIX2=$SQL_FIELDPREFIX1   #
SQL_FIELDPREFIX3=old_values          #

# Для Oracle:
#   SQL_CURSORNAME=cur
#   SQL_FIELDPREFIX1=
#   SQL_FIELDPREFIX2=$SQL_CURSORNAME.

SQL_PREFIX_DELTABLE=del              # Префикс в названии таблиц, содержащих
                                     # удаленные записи соответствующих
                                     # таблиц
SQL_PREFIX_TEMPTABLE=temp            # Префикс в названии временных таблиц
                                     # для загрузки данных (update)
SQL_PREFIX_UNLOADTABLE=unload        # Префикс в названии временных таблиц
                                     # для выгрузки данных (prepare)

SQL_COUNT_FILE=$PATH_TEMP/new_packet # файл, куда помещается номер
                                     # сформированного пакета

# ********************************************************************
# Таблица соответствий между кодами типов полей в метаданных и
# написанием типов в операторе create table стандарта SQL 92.
#
# Формат: type_<код типа>='<название типа>'[([,]]
#
#         Если указана открывающаяся скобка,
#         то в определении поля данного типа
#         должен указываться ее размер.
#         Если плюс к этой скобке указана
#         запятая, то размер должен состоять
#         из двух частей.

type_char='char('
type_varchar='varchar('
type_smallint='smallint'
type_integer='integer'
type_numeric='numeric(,'
type_float='float('
type_double='double'
type_date='date'
type_time='time'
type_timestamp='timestamp'
type_binary='binary('

# ********************************************************************
# Шаблоны SQL-выражений

# SQL-скрипт обновления существующих системных таблиц.
# Должен выполняться ДО выполнения SQL-скрипта обновления
# системы.

SQL_SYSTEM_UPGRADE=\
"
"

# SQL-скрипт создания служебных таблиц

SQL_SYSTEM_TABLE1=\
"
create table syncMAIN
(
  version_major smallint not null,
  version_minor smallint not null,
  current_packet int not null default 0
);
"

SQL_SYSTEM_TABLE2=\
"
create table syncNODES
(
  name varchar(30) not null unique,
  prepared int not null default 0,
  updated int not null default 0,
);
"

SQL_SYSTEM_TABLE3=\
"
create table syncSTREAM
(
  sender varchar(30) not null,
  receiver varchar(30) not null,
  stage int not null,
  num_packet int not null,
  time_packet timestamp not null default current timestamp,

  primary key (sender, receiver, stage, num_packet)
);
"

# SQL-скрипт создания служебных триггеров
# Параметры шаблона:
#   this - имя данного узла

SQL_SYSTEM_TRIGGERS=\
"
if exists(select * from SYS.SYSTRIGGERS
           where trigname = 'syncNODES_Stream_AU')
then
  drop trigger syncNODES_Stream_AU;
end if;

create trigger syncNODES_Stream_AU
  after update on syncNODES
  referencing
    old as old_values
    new as new_values
  for each row
begin

  if old_values.prepared < new_values.prepared
  then
    insert into syncSTREAM(sender, receiver, stage, num_packet, time_packet)
      values('<this>', new_values.name, 0, new_values.prepared, now(*));
  end if;

  if old_values.updated < new_values.updated
  then
    insert into syncSTREAM(sender, receiver, stage, num_packet, time_packet)
      values(new_values.name, '<this>', 1, new_values.updated, now(*));
  end if;

end
"

# SQL-скрипт установки в БД всего необходимого для системы.
# Параметры шаблона:
#   this           - имя данного узла
#   data_ver_major - версия метаданных
#   data_ver_minor - версия метаданных

SQL_SYSTEM_INSTALL=\
"
if exists(select * from SYS.SYSTABLE
           where table_name = 'syncMAIN')
then
  drop table syncMAIN;
end if;

$SQL_SYSTEM_TABLE1

if exists(select * from SYS.SYSTABLE
           where table_name = 'syncNODES')
then
  drop table syncNODES;
end if;

$SQL_SYSTEM_TABLE2

if exists(select * from SYS.SYSTABLE
           where table_name = 'syncSTREAM')
then
  drop table syncSTREAM;
end if;

$SQL_SYSTEM_TABLE3

$SQL_SYSTEM_TRIGGERS
go

insert into syncMAIN(version_major, version_minor)
              values(<data_ver_major>, <data_ver_minor>);

commit work;
"

# SQL-скрипт обновления системы в БД.
# Если необходимо выполнить SQL-скрипт обновления существующих
# системных таблиц, то он должен выполняться ДО выполнения
# данного скрипта.
# Параметры шаблона:
#   this           - имя данного узла
#   data_ver_major - версия метаданных
#   data_ver_minor - версия метаданных

SQL_SYSTEM_UPDATE=\
"
if not exists(select * from SYS.SYSTABLE
               where table_name = 'syncMAIN')
then
$SQL_SYSTEM_TABLE1
end if;

if not exists(select * from SYS.SYSTABLE
               where table_name = 'syncNODES')
then
$SQL_SYSTEM_TABLE2
end if;

if not exists(select * from SYS.SYSTABLE
               where table_name = 'syncSTREAM')
then
$SQL_SYSTEM_TABLE3
end if;

$SQL_SYSTEM_TRIGGERS
go

begin
  declare cur_packet int;

  select first current_packet
    into cur_packet
    from syncMAIN;

  if cur_packet is null
  then
    set cur_packet = 0;
  end if;

  delete from syncMAIN;
  insert into syncMAIN(version_major, version_minor, current_packet)
                values(<data_ver_major>, <data_ver_minor>, cur_packet);
end;

commit work;
"

# SQL-скрипт удаления из БД всего, что относится к системе

SQL_SYSTEM_UNINSTALL=\
"
if exists(select * from SYS.SYSTABLE
           where table_name = 'syncNODES')
then
  drop table syncNODES;
end if;

if exists(select * from SYS.SYSTABLE
           where table_name = 'syncSTREAM')
then
  drop table syncSTREAM;
end if;

if exists(select * from SYS.SYSTABLE
           where table_name = 'syncMAIN')
then
  drop table syncMAIN;
end if;
"

# Вернуть признак установлена ли система в базе данных.
# Любое значение - система установлена,
# ничего - система не установлена.

SQL_SYSTEM_STATUS=\
"
select 'ok'
  from SYS.SYSTABLE
 where table_name='syncMAIN'
"

# Вернуть версию метаданных системы в БД

SQL_SYSTEM_STATUS_VERSION=\
"
select version_major || '.' || version_minor
  from syncMAIN
"

# Вернуть текущий номер пакета

SQL_SYSTEM_STATUS_COVER=\
"
select first current_packet
  from syncMAIN
"

# Вернуть список удаленных узлов, зарегистрированных в системе

SQL_SYSTEM_STATUS_NODES=\
"
select name || '\\t[' || prepared || ',' || updated || ']'
  from syncNODES
 order by name
"

# SQL-скрипт добавления в систему удаленного узла

SQL_NODE_ADD=\
"
insert into syncNODES(name) values('<node>')
"

# SQL-скрипт удаления из системы удаленного узла

SQL_NODE_REMOVE=\
"
if exists(select * from SYS.SYSTABLE
           where table_name = 'syncNODES')
then
  delete from syncNODES
   where name = '<node>';
end if;
"

# Вернуть список удаленных узлов, зарегистрированных в системе

SQL_NODELIST=\
"
select name
  from syncNODES
 order by name
"

# SQL-скрипт создания таблицы для удаленных записей
# Параметры шаблона:
#   owner          - владелец таблицы
#   table          - имя таблицы
#   all_fields_def - определения всех полей таблицы (кроме служебных полей)
#                    из удаленной БД, перечисленные через запятую

SQL_WATCHDELETE_TABLE=\
"
-- Таблица для хранения стертых записей.
-- Хранить необходимо не только ключевые
-- поля, но и все остальные, так как
-- они могут понадобиться для фильтрации
-- (см. nodeconf). Кроме того, удаленные
-- записи передаются целиком, так как
-- на принимающей стороне таблица может
-- иметь первичный ключ, содержащий поля,
-- не входящие в первичный ключ исходной
-- таблицы.

create table <owner>.<table>_$SQL_PREFIX_DELTABLE
(
  <all_fields_def>,
  $SQL_SYSFIELD1 int not null default 0,
  $SQL_SYSFIELD2 int not null default 0
);
"

# SQL-скрипт создания триггера на удаление записи
# Параметры шаблона:
#   owner          - владелец таблицы
#   table          - имя таблицы
#   all_fields     - список всех полей таблицы (кроме служебных полей),
#                    перечисленных через запятую
#   all_values     - список всех полей таблицы (кроме служебных полей)
#                    в виде:
#                      old_values.<field1>,
#                      old_values.<field2>,
#                      ...
#                      old_values.<fieldN>

SQL_WATCHDELETE_TRIGGER=\
"
create trigger <owner>.<table>_sync_AD

-- Триггер для фиксирования факта удаления записи.
-- Фиксируются только записи, хоть раз попавшие
-- в какой-либо пакет для отправки
-- (SQL_SYSFIELD2 <> 0)

  after delete order 999 on <owner>.<table>
  referencing
    old as $SQL_FIELDPREFIX3
  for each row
  when ($SQL_FIELDPREFIX3.$SQL_SYSFIELD2 <> 0)
begin
  insert into <owner>.<table>_$SQL_PREFIX_DELTABLE(
          <all_fields>,
          $SQL_SYSFIELD1,
          $SQL_SYSFIELD2)
    values(
          <all_values>,
          0,
          $SQL_FIELDPREFIX3.$SQL_SYSFIELD2
         );
end;
"

# Общая часть SQL-скриптов для добавления/обновления таблицы для
# ее синхронизации.
# Параметры шаблона:
#   owner          - владелец таблицы
#   table          - имя таблицы
#   all_fields_def - определения всех полей таблицы (кроме служебных полей)
#                    из удаленной БД, перечисленные через запятую
#   change_fields  - список всех полей таблицы (кроме служебных полей)
#                    в виде:
#                      old_values.<field1> <> new_values.<field1> or
#                      old_values.<field2> <> new_values.<field2> or
#                      ...
#                      old_values.<fieldN> <> new_values.<fieldN> or

SQL_TABLE_COMMON=\
"
if not exists(select * from SYS.SYSCOLUMNS
               where tname = '<table>'
                 and creator = '<owner>'
                 and cname = '$SQL_SYSFIELD1')
then
  alter table <owner>.<table> add $SQL_SYSFIELD1 int default 0;
  update <owner>.<table> set $SQL_SYSFIELD1 = 0;
  alter table <owner>.<table> modify $SQL_SYSFIELD1 not null;
end if;

if not exists(select * from SYS.SYSCOLUMNS
               where tname = '<table>'
                 and creator = '<owner>'
                 and cname = '$SQL_SYSFIELD2')
then
  alter table <owner>.<table> add $SQL_SYSFIELD2 int default 0;
  update <owner>.<table> set $SQL_SYSFIELD2 = 0;
  alter table <owner>.<table> modify $SQL_SYSFIELD2 not null;
end if;

if not exists(select * from SYS.SYSINDEXES
               where iname = 'i_<owner>_<table>_$SQL_SYSFIELD1')
then
  create index i_<owner>_<table>_$SQL_SYSFIELD1 on <owner>.<table>($SQL_SYSFIELD1);
end if;

if exists(select * from SYS.SYSTRIGGERS
           where trigname = '<table>_sync_BU1'
             and owner = '<owner>')
then
  drop trigger <owner>.<table>_sync_BU1;
end if;

create trigger <owner>.<table>_sync_BU1

-- Триггер для определения номера пакета (SQL_SYSFIELD2),
-- в который запись попала впервые.

  before update order 989 on <owner>.<table>
  referencing
    old as old_values
    new as new_values
  for each row
  when (
       new_values.$SQL_SYSFIELD1 <> old_values.$SQL_SYSFIELD1
   and new_values.$SQL_SYSFIELD1 <> -1
   and old_values.$SQL_SYSFIELD2 = 0
       )
begin
  set new_values.$SQL_SYSFIELD2 = new_values.$SQL_SYSFIELD1;
end
go

if exists(select * from SYS.SYSTRIGGERS
           where trigname = '<table>_sync_BU2'
             and owner = '<owner>')
then
  drop trigger <owner>.<table>_sync_BU2;
end if;

create trigger <owner>.<table>_sync_BU2

-- Триггер для отслеживания изменения записи.
-- Триггер должен срабатывать после всех триггеров,
-- вызываемых до изменения записи и только в случае,
-- если изменились значения любых полей, кроме
-- служебных (другими словами, изменение значения
-- любого из служебных полей не должно приводить
-- к вызову данного триггера).

  before update order 999 on <owner>.<table>
  referencing
    old as old_values
    new as new_values
  for each row
  when (
       new_values.$SQL_SYSFIELD1 = old_values.$SQL_SYSFIELD1
   and new_values.$SQL_SYSFIELD2 = old_values.$SQL_SYSFIELD2
   and (<change_fields>)
       )
begin
  set new_values.$SQL_SYSFIELD1 = 0;
end
go

if exists(select * from SYS.SYSCATALOG
           where tname = '<table>_$SQL_PREFIX_DELTABLE'
             and creator = '<owner>'
             and tabletype = 'TABLE')
then
  drop table <owner>.<table>_$SQL_PREFIX_DELTABLE;
end if;

$SQL_WATCHDELETE_TABLE
"

# SQL-скрипт инициализации какой-либо таблицы для последующей
# ее синхронизации.
# Параметры шаблона:
#   owner          - владелец таблицы
#   table          - имя таблицы
#   all_fields_def - определения всех полей таблицы (кроме служебных полей)
#                    из удаленной БД, перечисленные через запятую
#   all_fields     - список всех полей таблицы (кроме служебных полей),
#                    перечисленных через запятую
#   all_values     - список всех полей таблицы (кроме служебных полей)
#                    в виде:
#                      old_values.<field1>,
#                      old_values.<field2>,
#                      ...
#                      old_values.<fieldN>
#   change_fields  - список всех полей таблицы (кроме служебных полей)
#                    в виде:
#                      old_values.<field1> <> new_values.<field1> or
#                      old_values.<field2> <> new_values.<field2> or
#                      ...
#                      old_values.<fieldN> <> new_values.<fieldN> or

SQL_TABLE_ADD=\
"
$SQL_TABLE_COMMON

if exists(select * from SYS.SYSTRIGGERS
           where trigname = '<table>_sync_AD'
             and owner = '<owner>')
then
  drop trigger <owner>.<table>_sync_AD;
end if;

$SQL_WATCHDELETE_TRIGGER
go
"

# SQL-скрипт обновления метаданных синхронизируемой таблицы
# Параметры шаблона:
#   owner          - владелец таблицы
#   table          - имя таблицы
#   all_fields_def - определения всех полей таблицы (кроме служебных полей)
#                    из удаленной БД, перечисленные через запятую
#   all_fields     - список всех полей таблицы (кроме служебных полей),
#                    перечисленных через запятую
#   all_values     - список всех полей таблицы (кроме служебных полей)
#                    в виде:
#                      old_values.<field1>,
#                      old_values.<field2>,
#                      ...
#                      old_values.<fieldN>
#   change_fields  - список всех полей таблицы (кроме служебных полей)
#                    в виде:
#                      old_values.<field1> <> new_values.<field1> or
#                      old_values.<field2> <> new_values.<field2> or
#                      ...
#                      old_values.<fieldN> <> new_values.<fieldN> or

SQL_TABLE_UPDATE=\
"
$SQL_TABLE_COMMON

if exists(select * from SYS.SYSTRIGGERS
           where trigname = '<table>_sync_AD'
             and owner = '<owner>')
then
  drop trigger <owner>.<table>_sync_AD;
  $SQL_WATCHDELETE_TRIGGER
end if;
go
"

# SQL-скрипт выключения таблицы из процесса синхронизации

SQL_TABLE_REMOVE=\
"
if exists(select * from SYS.SYSTRIGGERS
           where trigname = '<table>_sync_AD'
             and owner = '<owner>')
then
  drop trigger <owner>.<table>_sync_AD;
end if;

if exists(select * from SYS.SYSTRIGGERS
           where trigname = '<table>_sync_BU1'
             and owner = '<owner>')
then
  drop trigger <owner>.<table>_sync_BU1;
end if;

if exists(select * from SYS.SYSTRIGGERS
           where trigname = '<table>_sync_BU2'
             and owner = '<owner>')
then
  drop trigger <owner>.<table>_sync_BU2;
end if;

if exists(select * from SYS.SYSINDEXES
           where iname = 'i_<owner>_<table>_$SQL_SYSFIELD1')
then
  drop index i_<owner>_<table>_$SQL_SYSFIELD1;
end if;

if exists(select * from SYS.SYSCOLUMNS
           where tname = '<table>'
             and creator = '<owner>'
             and cname = '$SQL_SYSFIELD1')
then
  alter table <owner>.<table> drop $SQL_SYSFIELD1;
end if;

if exists(select * from SYS.SYSCOLUMNS
           where tname = '<table>'
             and creator = '<owner>'
             and cname = '$SQL_SYSFIELD2')
then
  alter table <owner>.<table> drop $SQL_SYSFIELD2;
end if;

if exists(select * from SYS.SYSCATALOG
           where tname = '<table>_$SQL_PREFIX_DELTABLE'
             and creator = '<owner>'
             and tabletype = 'TABLE')
then
  drop table <owner>.<table>_$SQL_PREFIX_DELTABLE;
end if;

if exists(select * from SYS.SYSCATALOG
           where tname = '<table>_$SQL_PREFIX_UNLOADTABLE'
             and creator = '<owner>'
             and tabletype = 'GBL TEMP')
then
  drop table <owner>.<table>_$SQL_PREFIX_UNLOADTABLE;
end if;
"

# SQL-скрипт включения слежения за удалением записей.
# Параметры шаблона:
#   owner          - владелец таблицы
#   table          - имя таблицы
#   all_fields_def - определения всех полей таблицы (кроме служебных полей)
#                    из удаленной БД, перечисленные через запятую
#   all_fields     - список всех полей таблицы (кроме служебных полей),
#                    перечисленных через запятую
#   all_values     - список всех полей таблицы (кроме служебных полей)
#                    в виде:
#                      old_values.<field1>,
#                      old_values.<field2>,
#                      ...
#                      old_values.<fieldN>

SQL_WATCHDELETE_ADD=\
"
if not exists(select * from SYS.SYSCATALOG
               where tname = '<table>_$SQL_PREFIX_DELTABLE'
                 and creator = '<owner>'
                 and tabletype = 'TABLE')
then
  $SQL_WATCHDELETE_TABLE
end if;

if exists(select * from SYS.SYSTRIGGERS
           where trigname = '<table>_sync_AD'
             and owner = '<owner>')
then
  drop trigger <owner>.<table>_sync_AD;
end if;

$SQL_WATCHDELETE_TRIGGER

go
"

# SQL-скрипт выключения слежения за удалением записей.
# Параметры шаблона:
#   owner          - владелец таблицы
#   table          - имя таблицы

SQL_WATCHDELETE_REMOVE=\
"
if exists(select * from SYS.SYSTRIGGERS
           where trigname = '<table>_sync_AD'
             and owner = '<owner>')
then
  drop trigger <owner>.<table>_sync_AD;
end if;
"

# SQL-скрипт удаления таблицы

SQL_REMOVE_TABLE=\
"
drop table <owner>.<table>;
"

# Вернуть список временных таблиц в формате
# <владелец>.<имя таблицы>

SQL_TEMPTABLELIST=\
"
select distinct creator || '.' || tname
  from SYS.SYSCOLUMNS
 where tname like '%\_${SQL_PREFIX_TEMPTABLE}' escape '\'
    or tname like '%\_${SQL_PREFIX_UNLOADTABLE}' escape '\'
"

# Вернуть список синхронизируемых таблиц в формате
# <владелец>.<имя таблицы>

SQL_TABLELIST=\
"
select creator || '.' || tname
  from SYS.SYSCOLUMNS
 where cname = '$SQL_SYSFIELD1'
   and tname not like '%\_$SQL_PREFIX_DELTABLE' escape '\'
   and tname not like '%\_$SQL_PREFIX_TEMPTABLE' escape '\'
   and tname not like '%\_$SQL_PREFIX_UNLOADTABLE' escape '\'
"

# Установить номер последнего успешно сформированного пакета
# для определенного удаленного узла

SQL_PACKET_PREPARED_SET=\
"
update syncNODES
   set prepared = <number>
 where name = '<node>';
"

# Вернуть номер последнего успешно сформированного пакета
# для определенного удаленного узла

SQL_PACKET_PREPARED_GET=\
"
select prepared
  from syncNODES
 where name = '<node>'
"

# Установить номер последнего успешно обработанного пакета
# для определенного удаленного узла

SQL_PACKET_UPDATED_SET=\
"
  update syncNODES
     set updated = <number>
   where name = '<node>';
"

# Вернуть номер последнего успешно обработанного пакета
# для определенного удаленного узла

SQL_PACKET_UPDATED_GET=\
"
select updated
  from syncNODES
 where name = '<node>'
"
# Структура шаблонов SQL-скрипта подготовки пакета:
#
# SQL_DATA_PREPARE_BEFORE           - начало SQL-скрипта подготовки пакета
#   SQL_DATA_PREPARE_BLOCK_BEG      - начало блока из N таблиц
#     SQL_DATA_PREPARE_[TABLE|VIEW] - для каждой таблицы или представления
#     ..                              в блоке
#   SQL_DATA_PREPARE_BLOCK_END      - конец блока из N таблиц
# SQL_DATA_PREPARE_AFTER            - конец SQL-скрипта подготовки пакета

# SQL-скрипт для формирования пакета - НАЧАЛО
# Параметры шаблона:
#   node - имя удаленного узла для которого готовится пакет

SQL_DATA_PREPARE_BEFORE=\
"
set temporary option Date_format = 'YYYY-MM-DD';
set temporary option Timestamp_format = 'YYYY-MM-DD HH:NN:SS.SSS';
set temporary option Time_format = 'HH:NN:SS.SSS';

create variable packet_data_exists int;
create variable new_packet_number int;
create variable packet_prepared int;

set packet_data_exists = 0;

-- Получить номер генерируемого пакета

select first current_packet + 1
  into new_packet_number
  from syncMAIN;

-- Получить номер последнего успешно сгенерированного
-- пакета для данного узла

select prepared
  into packet_prepared
  from syncNODES
 where name = '<node>';

-- Если необходимо, создать временную таблицу для
-- выгрузки в файл номера сгенерированного пакета

if not exists(select tname from SYS.SYSCATALOG
               where tname = 'syncCOUNT')
then
  create global temporary table syncCOUNT
  (
    value int
  ) on commit delete rows;
end if;
"

# SQL-скрипт для формирования пакета - НАЧАЛО БЛОКА ТАБЛИЦ

SQL_DATA_PREPARE_BLOCK_BEG=\
"
-- Начало блока begin/end

begin

  declare block_data_exists int;
  set block_data_exists = 0;
"

# SQL-скрипт для формирования пакета - ДЛЯ ОТДЕЛЬНОЙ ТАБЛИЦЫ
# Параметры шаблона:
#   owner         - владелец таблицы
#   table         - имя таблицы
#   node          - имя удаленного узла для которого готовится пакет
#   fields_def    - определения всех полей таблицы (кроме служебных полей),
#                   перечисленные через запятую
#   select_fields - названия всех полей (кроме служебных) в виде списка:
#                     $<field1> as $SQL_FIELDPREFIX1<field1>,
#                     $<field2> as $SQL_FIELDPREFIX1<field2>,
#                     ...
#                     $<fieldN> as $SQL_FIELDPREFIX1<fieldN>,
#                   Виртуальные поля в форме:
#                     <значение> as $SQL_FIELDPREFIX1<поле>
#   insert_fields - названия полей из select_fields в виде:
#                     <field1>,
#                     <field2>,
#                     ...
#                     <fieldN>
#   insert_values - названия полей из insert_fields в виде:
#                     $SQL_FIELDPREFIX2<field1>,
#                     $SQL_FIELDPREFIX2<field2>,
#                     ...
#                     $SQL_FIELDPREFIX2<fieldN>
#   filter        - необязательное дополнительное условие на выборку
#                   данных из таблицы, присоединенное через and и
#                   обрамленное в круглые скобки
#   file_data     - полный путь и имя файла, куда будут складываться
#                   данные, выбранные из таблицы
#   file_del      - полный путь и имя файла, куда будут складываться
#                   значения первичного ключа записей, удаленных из
#                   таблицы со времени предыдущего формирования пакета

SQL_DATA_PREPARE_TABLE=\
"
  ----------- Prepare data for table <table>

  if exists(select tname from SYS.SYSCATALOG
             where creator = '<owner>'
               and tname   = '<table>_${SQL_PREFIX_UNLOADTABLE}')
  then
    drop table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE};
  end if;

  create global temporary table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE}
  (
   <fields_def>
  ) on commit delete rows;

  update <owner>.<table>
     set $SQL_SYSFIELD1 = new_packet_number
   where (
          $SQL_SYSFIELD1 = 0
         )
     <filter>;

  insert into <owner>.<table>_${SQL_PREFIX_UNLOADTABLE}(<insert_fields>)
       select <select_fields>
                 from <owner>.<table>
                where (
                       $SQL_SYSFIELD1 > packet_prepared
                      )
                  <filter>;

  if exists(select * from <owner>.<table>_${SQL_PREFIX_UNLOADTABLE})
  then
    set block_data_exists = 1;
  end if;

  unload from table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE}
           to '<file_data>'
       format 'ascii';

  truncate table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE};

  update <owner>.<table>_$SQL_PREFIX_DELTABLE
     set $SQL_SYSFIELD1 = new_packet_number
   where $SQL_SYSFIELD1 = 0
     and $SQL_SYSFIELD2 <= packet_prepared
     <filter>;

  insert into <owner>.<table>_${SQL_PREFIX_UNLOADTABLE}(<insert_fields>)
       select <select_fields>
                 from <owner>.<table>_$SQL_PREFIX_DELTABLE
                where $SQL_SYSFIELD1 > packet_prepared
                  and $SQL_SYSFIELD2 <= packet_prepared
                  <filter>;

  if exists(select * from <owner>.<table>_${SQL_PREFIX_UNLOADTABLE})
  then
    set block_data_exists = 1;
  end if;

  unload from table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE}
           to '<file_del>'
       format 'ascii';

  drop table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE};
"

# SQL-скрипт для формирования пакета - ДЛЯ ОТДЕЛЬНОГО ПРЕДСТАВЛЕНИЯ
# Параметры шаблона как для таблицы, плюс:
#   select_special  - названия всех служебных полей в виде списка:
#                       pkt_<field1> as ${SQL_FIELDPREFIX1}pkt_<field1>
#                       pkt_<field2> as ${SQL_FIELDPREFIX1}pkt_<field2>
#                       ...
#                       pkt_<fieldN> as ${SQL_FIELDPREFIX1}pkt_<fieldN>
#   changed_special - условие на изменение хотя бы одного из служебного
#                     поля (на основе шаблона SQL_DATA_PREPARE_VIEW_IF)
#   update_special  - обновление всех служебных полей (на основе шаблона
#                     SQL_DATA_PREPARE_VIEW_UPDATE)

SQL_DATA_PREPARE_VIEW=\
"
  ----------- Prepare data for view <table>

  if exists(select tname from SYS.SYSCATALOG
             where creator = '<owner>'
               and tname   = '<table>_${SQL_PREFIX_UNLOADTABLE}')
  then
    drop table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE};
  end if;

  create global temporary table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE}
  (
   <fields_def>
  ) on commit delete rows;

  for forLoop as ${SQL_CURSORNAME}_data
    cursor for select <select_fields>,
                      <select_special>
                 from <owner>.<table>
                where (
                       <changed_special>
                      )
                  <filter>
  do
    set block_data_exists = 1;

    insert into <owner>.<table>_${SQL_PREFIX_UNLOADTABLE}(<insert_fields>)
                values(<insert_values>);

    <update_special>
  end for;

  unload from table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE}
           to '<file_data>'
       format 'ascii';

  drop table <owner>.<table>_${SQL_PREFIX_UNLOADTABLE};
"

# SQL-скрипт для формирования пакета - ДЛЯ ОТДЕЛЬНОГО ПРЕДСТАВЛЕНИЯ
# Условие на изменение отдельного служебного поля

SQL_DATA_PREPARE_VIEW_IF=\
"
<special_field> = 0 or
<special_field> > packet_prepared
"

# SQL-скрипт для формирования пакета - ДЛЯ ОТДЕЛЬНОГО ПРЕДСТАВЛЕНИЯ
# Для изменения отдельного служебного поля

SQL_DATA_PREPARE_VIEW_UPDATE=\
"
    if ${SQL_FIELDPREFIX1}<special_field> = 0
    then
      update <owner>.<table>
         set <special_field> = new_packet_number
       where current of ${SQL_CURSORNAME}_data;
    end if;
"

# SQL-скрипт для формирования пакета - КОНЕЦ БЛОКА ТАБЛИЦ

SQL_DATA_PREPARE_BLOCK_END=\
"
-- Конец блока begin/end

  if block_data_exists <> 0
  then
    set packet_data_exists = packet_data_exists + 1;
  end if;

end
go
"

# SQL-скрипт для формирования пакета - КОНЕЦ

SQL_DATA_PREPARE_AFTER=\
"
-- Если были выгруженны хоть какие-либо данные...

if packet_data_exists > 0
then
  -- Обновить счетчик пакетов в базе данных

  update syncMAIN
     set current_packet = new_packet_number;

  -- И выгрузить его во внешний файл

  insert into syncCOUNT(value) values(new_packet_number);
  unload from table syncCOUNT to '$SQL_COUNT_FILE';

end if;
"

# SQL-скрипт для обновления данных - НАЧАЛО

SQL_DATA_UPDATE_BEFORE=\
"
begin
"

# SQL-скрипт для обновления данных - ДЛЯ ОТДЕЛЬНОЙ ТАБЛИЦЫ
# Параметры шаблона:
#   owner         - владелец таблицы
#   table         - имя таблицы
#   file_data     - полный путь и имя файла с данными таблицы с удаленной БД
#   file_del      - полный путь и имя файла со стертыми записями из таблицы
#                   с удаленной БД
#   fields_def    - определения всех полей таблицы (кроме служебных полей)
#                   из удаленной БД, перечисленные через запятую
#   select_fields - названия полей (кроме служебных), которые
#                   одновременно присутствуют в таблице в локальной и
#                   удаленной БД, в виде:
#                     $<field1> as $SQL_FIELDPREFIX1<field1>,
#                     $<field2> as $SQL_FIELDPREFIX1<field2>,
#                     ...
#                     $<fieldN> as $SQL_FIELDPREFIX1<fieldN>,
#   insert_fields - названия полей из common_fields в виде:
#                     $SQL_FIELDPREFIX2<field1>,
#                     $SQL_FIELDPREFIX2<field2>,
#                     ...
#                     $SQL_FIELDPREFIX2<fieldN>
#   insert_values - названия полей из insert_fields в виде:
#                     $SQL_FIELDPREFIX2<field1>,
#                     $SQL_FIELDPREFIX2<field2>,
#                     ...
#                     $SQL_FIELDPREFIX2<fieldN>
#   pkey_fields   - поля, входящие в первичный ключ таблицы в локальной
#                   БД в виде:
#                     <field1> = $SQL_FIELDPREFIX2<field1> and
#                     <field2> = $SQL_FIELDPREFIX2<field2> and
#                     ...
#                     <fieldN> = $SQL_FIELDPREFIX2<fieldN>
#   update_fields - поля из удаленной таблицы, значения по которым
#                   обновляются в локальной таблице (по другому -
#                   поля из common_fields за минусом pkey_fields)
#                   в виде:
#                     <field1> = $SQL_FIELDPREFIX2<field1>,
#                     <field2> = $SQL_FIELDPREFIX2<field2>,
#                     ...
#                     <fieldN> = $SQL_FIELDPREFIX2<fieldN>

# Примечания к реализации:
#
#  * В Sybase нет возможности обратиться напрямую к значениям
#    полей в курсоре. Реализуется это именованием полей
#    через 'as' в соответствующем select-е.
#  * Команда input не используется, так как она не может
#    выполняться в batch.
#  * Локальная временная таблица не используется, так как
#    команда load ее "не видит".
#  * Глобальная временная таблица объявляется как
#    on commit preserve rows, потому что так требует команда
#    load, которая по завершении делает commit.
#  * load предполагает расположение файлов на сервере.
#  * Sybase требует уникальности идентификатора курсора в пределах
#    скрипта. Поэтому в его имя добавлено имя таблицы.

SQL_DATA_UPDATE=\
"
  ----------- Update table <owner>.<table>

  if exists(select tname from SYS.SYSCATALOG
             where creator = '<owner>'
               and tname = '<table>_${SQL_PREFIX_TEMPTABLE}')
  then
    drop table <owner>.<table>_${SQL_PREFIX_TEMPTABLE};
  end if;

  create global temporary table <owner>.<table>_${SQL_PREFIX_TEMPTABLE}
  (
   <fields_def>
  ) on commit preserve rows;

  load into table <owner>.<table>_${SQL_PREFIX_TEMPTABLE}
       from '<file_del>'
     format 'ascii';

  for forLoop as ${SQL_CURSORNAME}_del
    cursor for select <select_fields>
                 from <owner>.<table>_${SQL_PREFIX_TEMPTABLE}
  do
    delete from <owner>.<table>
     where
           <pkey_fields>
    ;
  end for;

  truncate table <owner>.<table>_${SQL_PREFIX_TEMPTABLE};

  load into table <owner>.<table>_${SQL_PREFIX_TEMPTABLE}
       from '<file_data>'
     format 'ascii';

  for forLoop as ${SQL_CURSORNAME}_data
    cursor for select <select_fields>
                 from <owner>.<table>_${SQL_PREFIX_TEMPTABLE}
  do
    begin
      if exists( select * from <owner>.<table>
                  where <pkey_fields>)
      then
        update <owner>.<table>
           set
               <update_fields>
         where
               <pkey_fields>
        ;
      else
        insert into <owner>.<table>(<insert_fields>)
                    values(<insert_values>);
      end if;
    end
  end for;

  drop table <owner>.<table>_${SQL_PREFIX_TEMPTABLE};
"

# SQL-скрипт для обновления данных - КОНЕЦ

SQL_DATA_UPDATE_AFTER=\
"
  --------- End table section
$SQL_PACKET_UPDATED_SET

end
"

# Вернуть список всех полей определенной таблицы исключая системные поля.
# Список должен быть отсортирован по названию полей - сначала ключевые
# поля, затем все остальные.

SQL_FIELDLIST=\
"
select cname
  from SYS.SYSCOLUMNS
 where $SQL_UPPER(creator) = $SQL_UPPER('<owner>')
   and $SQL_UPPER(tname) = $SQL_UPPER('<table>')
   and cname not in ('$SQL_SYSFIELD1', '$SQL_SYSFIELD2')
   and $SQL_UPPER(cname) not like 'PKT\_%' escape '\'
 order by in_primary_key desc, cname asc
"

# Вернуть список ключевых или неключевых полей определенной
# таблицы исключая системные поля.
# Список должен быть отсортирован по названию полей.

SQL_FIELDLIST_EX=\
"
select cname
  from SYS.SYSCOLUMNS
 where $SQL_UPPER(creator) = $SQL_UPPER('<owner>')
   and $SQL_UPPER(tname) = $SQL_UPPER('<table>')
   and cname not in ('$SQL_SYSFIELD1', '$SQL_SYSFIELD2')
   and $SQL_UPPER(cname) not like 'PKT\_%' escape '\'
   and in_primary_key <equal_or_not> '$SQL_FIELD_IN_PKEY'
 order by cname asc
"

# Вернуть список всех служебных полей определенной таблицы

SQL_FIELDLIST_SPECIAL=\
"
select cname
  from SYS.SYSCOLUMNS
 where $SQL_UPPER(creator) = $SQL_UPPER('<owner>')
   and $SQL_UPPER(tname) = $SQL_UPPER('<table>')
   and $SQL_UPPER(cname) like 'PKT\_%' escape '\'
 order by cname asc
"

# Список метаданных о полях определенной таблицы исключая системные поля.
# Список должен состоять из строк с пятью полями, разделенных пробелом:
#   <имя поля> <входит в перв.ключ?> <код типа поля> <размер1> <размер2>
# и быть отсортированным по названию полей - сначала ключевые поля,
# затем все остальные.

SQL_FIELDLIST_META=\
"
select cname          || '$SQL_FIELD_SEPARATOR' ||
       in_primary_key || '$SQL_FIELD_SEPARATOR' ||
       coltype        || '$SQL_FIELD_SEPARATOR' ||
       length         || '$SQL_FIELD_SEPARATOR' ||
       syslength
  from SYS.SYSCOLUMNS
 where creator = $SQL_UPPER('<owner>')
   and tname = $SQL_UPPER('<table>')
   and cname not in ('$SQL_SYSFIELD1', '$SQL_SYSFIELD2')
 order by in_primary_key desc, cname asc
"

# Вернуть что-либо, если указанная таблица является
# представлением (view)

SQL_ISVIEW=\
"
select 1 from SYS.SYSCATALOG
 where $SQL_UPPER(creator) = $SQL_UPPER('<owner>')
   and $SQL_UPPER(tname) = $SQL_UPPER('<table>')
   and tabletype = 'VIEW'
"

# ********************************************************************
# sql_valuelist - Вернуть список значений из базы данных
# -------------
# Параметры:
#   sqlname - имя переменной, хранящей SQL-выражение
#   sql     - необязательно. Само SQL-выражение,
#             возвращающее список значений
#
# Если не задан второй аргумент, то SQL-выражение берется из
# переменной, имя которой указанно в первом аргументе.
#
# В случае возникновения ошибки при выполнении SQL-выражения
# функция возвращает специальное значение $SQL_ERROR.
#
# Внимание! Реализация функции зависит от СУБД.

sql_valuelist()
{
  typeset sql tmpfile errfile list rawstr

  sqlname=$1
  sql="$2"

  tmpfile=$PATH_TEMP/$$-sql_valuelist.dat
  errfile=$PATH_TEMP/error_sql-$$.sql

  if [ ! -x $SQL_EXEC ]
  then
    logmsg $ST_ERR 1 0 $0 "Программа \"$SQL_EXEC\" недоступна или не может быть выполнена"
    echo "$SQL_ERROR"
    return
  fi

  if [ -z "$sql" ]
  then
    sql="$(value_by_name $sqlname)"
    if [ -z "$sql" ]
    then
      logmsg $ST_ERR 1 0 $0 "Пустое SQL-выражение, которое дожно возвращать список значений"
      echo "$SQL_ERROR"
      return
    fi
  fi
  sql="$sql ># $tmpfile"

  # Получить список значений из БД

  $SQL_EXEC "$sql" 2> $errfile
  if [ $? -ne 0 ]
  then
    rm -f $tmpfile
    echo "$sql" >> $errfile
    logmsg $ST_ERR 1 0 $0 "Ошибка при выполнении SQL-выражения \"$sqlname\". Выражение сохранено в файле \"$errfile\""
    echo "$SQL_ERROR"
    return
  fi

  list="`cat $tmpfile`"
  rm -f $tmpfile
  rm -f $errfile

  rawstr=`printf "%s" "$list"`
  logmsg $ST_INFO 3 0 $0 "SQL-выражение \"$sqlname\" вернуло список \"$rawstr\""

  # Убрать кавычки вокруг значений, если они есть
  # (например, для строковых значений) и вернуть
  # итоговую строку

  replace "$list" "'" ""
}

# ********************************************************************
