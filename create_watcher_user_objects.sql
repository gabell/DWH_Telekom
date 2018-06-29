/***********************************************/
/* DEBUG -                             Watcher */
/***********************************************/

    --drop table run_stats;
    CREATE GLOBAL TEMPORARY TABLE run_stats
    ( 
        runid varchar2(15),
        name varchar2(80),
        value int 
    )
    ON COMMIT PRESERVE ROWS;
    /
    
    --drop table debugtab;
    CREATE TABLE debugtab
    (
        userid          varchar2(30),
        filename        varchar2(1024),
        modules         varchar2(4000),
        show_date       varchar2(3),
        date_format    varchar2(255),
        name_length     number,
        session_id      varchar2(3),
        audsid          number,
        sub_module      varchar2(50),
      --
      -- Constraints
      --
      CONSTRAINT debugtab_show_date_ck CHECK ( show_date IN ( 'YES', 'NO' ) ),
      CONSTRAINT debugtab_session_id_ck CHECK ( session_id IN ( 'YES', 'NO' ) )
    );
    /
    
    CREATE UNIQUE INDEX debugtab_pk ON debugtab(userid, filename, audsid);
    /
    
    ALTER TABLE debugtab ADD CONSTRAINT debugtab_pk 
    PRIMARY KEY(userid, filename, audsid);
    /
    
    --drop table PROCEDURES_DEF;
    CREATE  TABLE procedures_def
    (
        idprocedure NUMBER(3, 0) NOT NULL,
        username VARCHAR2(30) NOT NULL,
        name VARCHAR2(50) NOT NULL,
        dscrpt VARCHAR2(255),
        minimtime NUMBER(10,2),
        maximtime NUMBER(10,2),
        avgtime NUMBER(10,2)       
    );
    /
    
    CREATE UNIQUE INDEX procedures_def_pk ON procedures_def(idprocedure);
    /
    
    ALTER TABLE procedures_def ADD CONSTRAINT procedures_def_pk
    PRIMARY KEY(idprocedure);
    /
    
    -- drop table tlog;
    CREATE  TABLE tlog
    (
        ID NUMBER NOT NULL,
        ldate DATE DEFAULT sysdate,
        lhsecs NUMBER,
        llevel NUMBER,
        lsection VARCHAR2(50),
        ltexte VARCHAR2(2000),
        luser VARCHAR2(30),
        granule NUMBER,
        piece NUMBER,
        startend VARCHAR2(10),
        who_call VARCHAR2(50),
        p1 VARCHAR2(50),
        p2 VARCHAR2(50)
    );
    /
    
    CREATE UNIQUE INDEX tlog_pk ON tlog(ID);
    /
    
    ALTER TABLE tlog ADD CONSTRAINT tlog_pk
    PRIMARY KEY(ID);
    /
    
    CREATE INDEX tlog_granule_nu_i ON tlog(granule);
    /
    
    -- drop table TLOGLEVEL;
    CREATE  TABLE tloglevel
    (
        llevel NUMBER(4, 0) NOT NULL,
        lsyslogequiv NUMBER(4, 0),
        lcode VARCHAR2(10),
        ldesc VARCHAR2(255)  
    );
    /
    
    INSERT INTO tloglevel
    (llevel, lsyslogequiv, lcode, ldesc)
    VALUES
    (10, NULL, 'OFF', 'The OFF has the highest possible rank and is intended to turn off logging.');
    /
    INSERT INTO tloglevel
    (llevel, lsyslogequiv, lcode, ldesc)
    VALUES
    (20, NULL, 'FATAL', 'The FATAL level designates very severe error events that will presumably lead the application to abort.');
    /
    INSERT INTO tloglevel
    (llevel, lsyslogequiv, lcode, ldesc)
    VALUES
    (30, NULL, 'ERROR', 'the ERROR level designates error events that might still allow the application  to continue running.');
    /
    INSERT INTO tloglevel
    (llevel, lsyslogequiv, lcode, ldesc)
    VALUES
    (40, NULL, 'WARN', 'The WARN level designates potentially harmful situations.');
    /
    INSERT INTO tloglevel
    (llevel, lsyslogequiv, lcode, ldesc)
    VALUES
    (50, NULL, 'INFO', 'The INFO level designates informational messages that highlight the progress of the application at coarse-grained level.');
    /
    INSERT INTO tloglevel
    (llevel, lsyslogequiv, lcode, ldesc)
    VALUES
    (60, NULL, 'DEBUG', 'The DEBUG Level designates fine-grained informational events that are most useful to debug an application.');
    /
    INSERT INTO tloglevel
    (llevel, lsyslogequiv, lcode, ldesc)
    VALUES
    (70, NULL, 'ALL', 'The ALL has the lowest possible rank and is intended to turn on all logging.');
    /
    COMMIT
    /

/***********************************************/
/* SEQUENCE - Watcher                          */
/***********************************************/
    --drop sequence SLOG;
    CREATE SEQUENCE SLOG
        START WITH    1
        INCREMENT BY  1
        MINVALUE      1
        MAXVALUE      1E28
        CYCLE
        NOORDER
        CACHE         20
    /

/***********************************************/
/* VIEWs - Watcher                             */
/***********************************************/
    --drop view v_stats;
    CREATE OR REPLACE VIEW v_stats
    AS SELECT 'STAT...' || A.NAME NAME, b.VALUE
          FROM v$statname A, v$mystat b
         WHERE A.statistic# = b.statistic#
        UNION ALL
        SELECT 'LATCH.' || NAME,  gets
          FROM v$latch;
    /
    
    -- drop view V_SHOW_REPORT_ALL;
    CREATE OR REPLACE VIEW v_show_report_all
     (
         id, idprocedure, username, name,
         pstart, pend, run_time_min, lcode,
         error, who_call, p1, avgtime
    )
    AS
    SELECT ID,granule idprocedure,pd.username,pd.NAME NAME,
        pstart,pend,round(nvl((pend-pstart)*24*60*60,-1)/60) run_time_min,lcode,
        decode(lcode,'FATAL',ERROR) ERROR,who_call,p1,avgtime 
    FROM
        (SELECT ID, ldate pend,llevel,ltexte,
            luser, granule, piece, startend ,who_call, p1,
            decode(UPPER(startend),'_START_',TO_DATE(NULL),LAG(ldate) OVER (PARTITION BY piece,granule ORDER BY piece,granule,ID ASC)) pstart,
            llevel status,
            ltexte ERROR
        FROM tlog WHERE startend IN ('_START_','_END_')
        ORDER BY piece,granule,ID) tt, tloglevel tl, procedures_def pd
    WHERE tt.status=tl.llevel AND UPPER(startend)='_END_' AND tt.granule=pd.idprocedure;
/

/***********************************************/
/* DETRALOG PAKAGE - Watcher                   */
/***********************************************/
    --drop package detralog;
    CREATE OR REPLACE PACKAGE detralog AS
    
        nolevel CONSTANT NUMBER := -999.99 ;
        defaultextmess CONSTANT VARCHAR2(20) := 'None';
        g_who procedures_def.NAME%TYPE;
        g_who_call tlog.who_call%TYPE:='DAY';
        
        -- The OFF has the highest possible rank and is intended to turn off logging.
        loff   CONSTANT NUMBER := 10 ;
        -- The FATAL level designates very severe error events that will presumably lead the application to abort.
        lfatal CONSTANT NUMBER := 20 ;
        -- The ERROR level designates error events that might still allow the application  to continue running.
        lerror CONSTANT NUMBER := 30 ;
        -- The WARN level designates potentially harmful situations.
        lwarn  CONSTANT NUMBER := 40 ;
        -- The INFO level designates informational messages that highlight the progress of the application at coarse-grained level.
        linfo  CONSTANT NUMBER := 50 ;
        -- The DEBUG Level designates fine-grained informational events that are most useful to debug an application.
        ldebug CONSTANT NUMBER := 60 ;
        -- The ALL has the lowest possible rank and is intended to turn on all logging.
        lall   CONSTANT NUMBER := 70 ;
        
        TYPE log_ctx IS RECORD (
        isdefaultinit     BOOLEAN DEFAULT FALSE ,
        llevel            tlog.llevel%TYPE      ,
        lsection          tlog.lsection%TYPE    ,
        ltexte            tlog.ltexte%TYPE      ,
        use_out_trans     BOOLEAN               ,
        use_logtable      BOOLEAN               ,
        init_lsection     tlog.lsection%TYPE    ,
        init_llevel       tlog.llevel%TYPE      ,
        who_call          tlog.who_call%TYPE    ,
        p1                tlog.p1%TYPE          ,
        p2                tlog.p2%TYPE);
        
        TYPE argv IS TABLE OF VARCHAR2(4000);
        emptydebugargv argv;
        
        global_directory VARCHAR2(30):='MONITOR';
        tlog_start tlog.startend%TYPE:='_START_';
        tlog_end tlog.startend%TYPE:='_END_';
        tlog_cursor tlog.startend%TYPE:='CURSOR';
    
        -------------------------------------------------------------------
        -- Public Procedure and function
        -------------------------------------------------------------------
    
    
        PROCEDURE DEBUG
        (
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        
        PROCEDURE DEBUG
        (
            pctx        IN OUT NOCOPY log_ctx,
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        
        PROCEDURE info
        (
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        PROCEDURE info
        (
            pctx        IN OUT NOCOPY log_ctx,
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        
        PROCEDURE warn
        (
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        PROCEDURE warn
        (
            pctx        IN OUT NOCOPY log_ctx,
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        
        PROCEDURE ERROR
        (
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        
        PROCEDURE ERROR
        (
            pctx        IN OUT NOCOPY log_ctx,
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        
        PROCEDURE fatal
        (
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        PROCEDURE fatal
        (
            pctx        IN OUT NOCOPY log_ctx,
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        
        PROCEDURE LOG
        (
            pctx        IN OUT NOCOPY log_ctx,
            plevel      IN tlog.llevel%TYPE,
            ptexte      IN tlog.ltexte%TYPE DEFAULT defaultextmess,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        
        FUNCTION init
        (
            psection        IN tlog.lsection%TYPE DEFAULT NULL,
            plevel          IN tlog.llevel%TYPE   DEFAULT ldebug,
            plogtable       IN BOOLEAN            DEFAULT TRUE,
            pout_trans      IN BOOLEAN            DEFAULT TRUE,
            pcall           IN tlog.who_call%TYPE DEFAULT g_who_call,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        )
        RETURN log_ctx;
        
        PROCEDURE log_in_cursor
        (
            p_step IN OUT NUMBER,
            p_date IN OUT DATE,
            p_granule IN NUMBER,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        );
        
        PROCEDURE init(
            p_sub_module  IN VARCHAR2 DEFAULT NULL,
            p_user        IN VARCHAR2 DEFAULT USER,
            p_show_date   IN VARCHAR2 DEFAULT 'YES',
            p_date_format IN VARCHAR2 DEFAULT 'DD/MM/YYYY HH24:MI:SS',
            p_name_len    IN NUMBER   DEFAULT 30,
            p_show_sesid  IN VARCHAR2 DEFAULT 'YES' 
        );
        
        PROCEDURE F(
            p_message IN VARCHAR2,
            p_arg1    IN VARCHAR2 DEFAULT NULL,
            p_arg2    IN VARCHAR2 DEFAULT NULL,
            p_arg3    IN VARCHAR2 DEFAULT NULL,
            p_arg4    IN VARCHAR2 DEFAULT NULL,
            p_arg5    IN VARCHAR2 DEFAULT NULL,
            p_arg6    IN VARCHAR2 DEFAULT NULL,
            p_arg7    IN VARCHAR2 DEFAULT NULL,
            p_arg8    IN VARCHAR2 DEFAULT NULL,
            p_arg9    IN VARCHAR2 DEFAULT NULL,
            p_arg10   IN VARCHAR2 DEFAULT NULL 
        );
        
        -- debug.fa( 'List: %s,%s,%s,%s,%s,%s', argv( 1, 2, 'Test', 'Chris', 100, 10 ) );
        
        PROCEDURE fa(
            p_message IN VARCHAR2,
            p_args    IN argv DEFAULT emptydebugargv 
        );
        
        PROCEDURE CLEAR(p_user IN VARCHAR2 DEFAULT USER );
        
        FUNCTION which_object_call(
            p_level IN NUMBER DEFAULT 5,
            p_type IN VARCHAR2 DEFAULT 'OBJ') 
        RETURN VARCHAR2;
        
        PRAGMA restrict_references (which_object_call, wnds);
        
        PROCEDURE rs_start;
        PROCEDURE rs_middle;
        PROCEDURE rs_stop( p_difference_threshold IN NUMBER DEFAULT 0 );
        
        FUNCTION get_process_name(
            p_id IN procedures_def.idprocedure%TYPE,
            p_name_default IN procedures_def.NAME%TYPE DEFAULT 'UNKNOWN')
        RETURN procedures_def.NAME%TYPE;
    
    END detralog;
    /
    
    
    /***********************************************/
    /* DETRALOG PAKAGE BODY - Watcher              */
    /***********************************************/
    CREATE OR REPLACE PACKAGE BODY detralog AS
        g_session_id VARCHAR2(2000);
        g_start NUMBER;
        g_run1  NUMBER;
        g_run2  NUMBER;
        
        --------------------------------------------------------------------
        PROCEDURE who_called_me(
          o_owner  OUT VARCHAR2,
          o_object OUT VARCHAR2,
          o_lineno OUT NUMBER,
          p_level  IN NUMBER DEFAULT 6) IS
        --
          l_call_stack LONG DEFAULT dbms_utility.format_call_stack;
          l_line VARCHAR2(4000);
        BEGIN
          FOR I IN 1 .. p_level LOOP
            l_call_stack := substr( l_call_stack,
                            instr( l_call_stack, CHR(10) )+1 );
          END LOOP;
          l_line := LTRIM( substr( l_call_stack,
                                   1,
                                   instr( l_call_stack, CHR(10) ) - 1 ) );
          l_line := LTRIM( substr( l_line, instr( l_line, ' ' )));
          o_lineno := to_number(substr(l_line, 1, instr(l_line, ' ')));
          l_line := LTRIM(substr(l_line, instr(l_line, ' ')));
          l_line := LTRIM( substr( l_line, instr( l_line, ' ' )));
          IF l_line LIKE 'block%' OR
             l_line LIKE 'body%' THEN
             l_line := LTRIM( substr( l_line, instr( l_line, ' ' )));
          END IF;
          o_owner := LTRIM( RTRIM( substr( l_line,
                            1,
                            instr( l_line, '.' )-1 )));
          o_object  := LTRIM( RTRIM( substr( l_line,
                                     instr( l_line, '.' )+1 )));
          IF o_owner IS NULL THEN
            o_owner := USER;
            o_object := 'ANONYMOUS BLOCK';
          END IF;
        END who_called_me;
        
        --------------------------------------------------------------------
        FUNCTION which_object_call(p_level IN NUMBER DEFAULT 5,p_type IN VARCHAR2 DEFAULT 'OBJ')
         RETURN VARCHAR2 IS
          l_owner VARCHAR2(255);
          l_object VARCHAR2(255);
          l_lineno NUMBER;
        BEGIN
          who_called_me( l_owner, l_object, l_lineno, p_level );
          IF p_type='OBJ' THEN RETURN l_object;
           ELSIF p_type='ALL' THEN RETURN l_object||'['||l_lineno||']';
            ELSE
             RETURN l_lineno;
          END IF;
        END;
        
        --------------------------------------------------------------------
        FUNCTION build_it(
          p_debug_row IN debugtab%rowtype,
          p_owner     IN VARCHAR2,
          p_object    IN VARCHAR2,
          p_lineno NUMBER ) RETURN VARCHAR2 IS
        --
          l_header LONG := NULL;
        BEGIN
          IF p_debug_row. session_id = 'YES' THEN
            l_header := g_session_id || ' - ';
          END IF;
          IF p_debug_row.show_date = 'YES' THEN
            l_header := l_header ||
                        to_char( sysdate,
                        nvl( p_debug_row.DATE_FORMAT,
                        'MMDDYYYY HH24MISS' ) );
          END IF;
          l_header :=
                   l_header ||
                   '(' ||
                   lpad( substr( p_owner || '.' || p_object,
                   greatest( 1, LENGTH( p_owner || '.' || p_object ) -
                   least( p_debug_row.name_length, 61 ) + 1 ) ),
                   least( p_debug_row.name_length, 61 ) ) ||
                   lpad( p_lineno, 5 ) ||
                   ') ';
          RETURN l_header;
        END build_it;
        
        --------------------------------------------------------------------
        FUNCTION parse_it(
          p_message       IN VARCHAR2,
          p_argv          IN argv,
          p_header_length IN NUMBER ) RETURN VARCHAR2 IS
        --
          l_message LONG := NULL;
          l_str LONG := p_message;
          l_idx NUMBER := 1;
          l_ptr NUMBER := 1;
        BEGIN
          IF nvl( instr( p_message, '%' ), 0 ) = 0 AND
             nvl( instr( p_message, '\' ), 0 ) = 0 THEN
            RETURN p_message;
          END IF;
          LOOP
            l_ptr := instr( l_str, '%' );
            EXIT WHEN l_ptr = 0 OR l_ptr IS NULL;
            l_message := l_message || substr( l_str, 1, l_ptr-1 );
            l_str :=  substr( l_str, l_ptr+1 );
            IF substr( l_str, 1, 1 ) = 's' THEN
              l_message := l_message || p_argv(l_idx);
              l_idx := l_idx + 1;
              l_str := substr( l_str, 2 );
            ELSIF substr( l_str,1,1 ) = '%' THEN
              l_message := l_message || '%';
              l_str := substr( l_str, 2 );
            ELSE
              l_message := l_message || '%';
            END IF;
          END LOOP;
          l_str := l_message || l_str;
          l_message := NULL;
          LOOP
            l_ptr := instr( l_str, '\' );
            EXIT WHEN l_ptr = 0 OR l_ptr IS NULL;
            l_message := l_message || substr( l_str, 1, l_ptr-1 );
            l_str :=  substr( l_str, l_ptr+1 );
            IF substr( l_str, 1, 1 ) = 'n' THEN
              l_message := l_message || CHR(10) ||
              rpad( ' ', p_header_length, ' ' );
              l_str := substr( l_str, 2 );
            ELSIF substr( l_str, 1, 1 ) = 't' THEN
              l_message := l_message || CHR(9);
              l_str := substr( l_str, 2 );
            ELSIF substr( l_str, 1, 1 ) = '\' THEN
              l_message := l_message || '\';
              l_str := substr( l_str, 2 );
            ELSE
              l_message := l_message || '\';
            END IF;
          END LOOP;
          RETURN l_message || l_str;
        END parse_it;
        
        --------------------------------------------------------------------
        FUNCTION file_it(
          p_file    IN debugtab.filename%TYPE,
          p_message IN VARCHAR2 ) RETURN BOOLEAN IS
        --
          l_handle utl_file.file_type;
          l_file LONG;
          l_location LONG;
        BEGIN
          l_file := substr( p_file,
                    instr( REPLACE( p_file, '\', '/' ),
                    '/', -1 )+1 );
        
          --l_file:='EXPERT';
        
          /*l_location := substr( p_file,
                                1,
                                instr( replace( p_file, '\', '/' ),
                                '/', -1 )-1 );  */
        
          l_handle := utl_file.fopen(
                              -- location => l_location,
                              -- 'MONITOR',
                               global_directory,
                               filename => l_file,
                               open_mode => 'a',
                               max_linesize => 32767 );
          utl_file.put( l_handle, '' );
          utl_file.put_line( l_handle, p_message );
          utl_file.fclose( l_handle );
          RETURN TRUE;
          /*exception
            when others then
              if utl_file.is_open( l_handle ) then
                utl_file.fclose( l_handle );
              end if;
          return false; */
        END file_it;
        
        --------------------------------------------------------------------
        PROCEDURE debug_it(
          p_message IN VARCHAR2,
          p_argv    IN argv ) IS
        --
          l_message LONG := NULL;
          l_header LONG := NULL;
          call_who_called_me BOOLEAN := TRUE;
          l_owner VARCHAR2(255);
          l_object VARCHAR2(255);
          l_lineno NUMBER;
          l_dummy BOOLEAN;
        BEGIN
          FOR C IN ( SELECT *
                     FROM debugtab
                     WHERE userid = USER )
          LOOP
            IF call_who_called_me THEN
              who_called_me( l_owner, l_object, l_lineno );
              call_who_called_me := FALSE;
            END IF;
            IF instr( ',' || C.modules || ',',
                      ',' || l_object || C.sub_module || ',' ) <> 0 OR
              C.modules = 'ALL'
            THEN
              l_header := build_it( C, l_owner, l_object, l_lineno );
              l_message := parse_it( p_message, p_argv, LENGTH(l_header) );
              l_dummy := file_it( C.filename, l_header || l_message );
            END IF;
          END LOOP;
        END debug_it;
        
        --------------------------------------------------------------------
        PROCEDURE init(
          p_sub_module  IN VARCHAR2 DEFAULT NULL,
          p_user        IN VARCHAR2 DEFAULT USER,
          p_show_date   IN VARCHAR2 DEFAULT 'YES',
          p_date_format IN VARCHAR2 DEFAULT 'DD/MM/YYYY HH24:MI:SS',
          p_name_len    IN NUMBER   DEFAULT 30,
          p_show_sesid  IN VARCHAR2 DEFAULT 'YES' ) IS
        --
          PRAGMA autonomous_transaction;
          debugtab_rec debugtab%rowtype;
          l_message LONG;
          p_modules VARCHAR2(4000) DEFAULT 'ALL';
          p_file    VARCHAR2(1024) DEFAULT USER || '.dbg';
        BEGIN
        
           p_modules:=which_object_call(6)||p_sub_module;
           p_file:=p_modules||'.dbg';
        
           DELETE FROM debugtab
            WHERE userid = p_user
            AND audsid=g_session_id
            AND UPPER(filename)=UPPER(p_file);
        
          INSERT INTO debugtab(
            userid, modules, filename, show_date,
            DATE_FORMAT, name_length, session_id,audsid,sub_module )
          VALUES (
            p_user, p_modules, p_file, p_show_date,
            p_date_format, p_name_len, p_show_sesid,g_session_id,p_sub_module )
          RETURNING
            userid, modules, filename, show_date,
            DATE_FORMAT, name_length, session_id,audsid,sub_module
          INTO
            debugtab_rec.userid, debugtab_rec.modules,
            debugtab_rec.filename, debugtab_rec.show_date,
            debugtab_rec.DATE_FORMAT, debugtab_rec.name_length,
            debugtab_rec.session_id,debugtab_rec.audsid,debugtab_rec.sub_module;
        
          l_message := CHR(10) ||
                       'Debug parameters initialized on ' ||
                       to_char( sysdate, 'dd-MON-yyyy hh24:mi:ss' ) || CHR(10);
          l_message := l_message || '           USER: ' ||
                       debugtab_rec.userid || CHR(10);
          l_message := l_message || '        MODULES: ' ||
                       debugtab_rec.modules || CHR(10);
          l_message := l_message || '       FILENAME: ' ||
                       debugtab_rec.filename || CHR(10);
          l_message := l_message || '      SHOW DATE: ' ||
                       debugtab_rec.show_date || CHR(10);
          l_message := l_message || '    DATE FORMAT: ' ||
                       debugtab_rec.DATE_FORMAT || CHR(10);
          l_message := l_message || '    NAME LENGTH: ' ||
                       debugtab_rec.name_length || CHR(10);
          l_message := l_message || 'SHOW SESSION ID: ' ||
                       debugtab_rec.session_id || CHR(10);
          IF NOT file_it( debugtab_rec.filename, l_message ) THEN
            ROLLBACK;
            raise_application_error(
                        -20001,
                        'Can not open file "' ||
                        debugtab_rec.filename || '"' );
          END IF;
          COMMIT;
        END init;
        
        --------------------------------------------------------------------
        PROCEDURE F(
          p_message IN VARCHAR2,
          p_arg1    IN VARCHAR2 DEFAULT NULL,
          p_arg2    IN VARCHAR2 DEFAULT NULL,
          p_arg3    IN VARCHAR2 DEFAULT NULL,
          p_arg4    IN VARCHAR2 DEFAULT NULL,
          p_arg5    IN VARCHAR2 DEFAULT NULL,
          p_arg6    IN VARCHAR2 DEFAULT NULL,
          p_arg7    IN VARCHAR2 DEFAULT NULL,
          p_arg8    IN VARCHAR2 DEFAULT NULL,
          p_arg9    IN VARCHAR2 DEFAULT NULL,
          p_arg10   IN VARCHAR2 DEFAULT NULL ) IS
        BEGIN
          -- return;
          debug_it( p_message,
                    argv( substr( p_arg1, 1, 4000 ),
                          substr( p_arg2, 1, 4000 ),
                          substr( p_arg3, 1, 4000 ),
                          substr( p_arg4, 1, 4000 ),
                          substr( p_arg5, 1, 4000 ),
                          substr( p_arg6, 1, 4000 ),
                          substr( p_arg7, 1, 4000 ),
                          substr( p_arg8, 1, 4000 ),
                          substr( p_arg9, 1, 4000 ),
                          substr( p_arg10, 1, 4000 ) ) );
        END F;
        
        PROCEDURE fa(
          p_message IN VARCHAR2,
          p_args    IN argv DEFAULT emptydebugargv ) IS
        BEGIN
          -- return;
          debug_it( p_message, p_args );
        END fa;
        
        --------------------------------------------------------------------
        PROCEDURE CLEAR( p_user IN VARCHAR2 DEFAULT USER) IS
          PRAGMA autonomous_transaction;
          p_file    VARCHAR2(1024);
        BEGIN
          DELETE FROM debugtab WHERE userid = p_user AND audsid=g_session_id
          AND UPPER(filename)= UPPER(which_object_call(7)||sub_module||'.dbg');
          COMMIT;
        END CLEAR;
        
        --------------------------------------------------------------------
        PROCEDURE addrow
        (
          pid         IN tlog.ID%TYPE,
          pldate      IN tlog.ldate%TYPE,
          plhsecs     IN tlog.lhsecs%TYPE,
          pllevel     IN tlog.llevel%TYPE,
          plsection   IN tlog.lsection%TYPE,
          pluser      IN tlog.luser%TYPE,
          pltexte     IN tlog.ltexte%TYPE,
          pgranule    IN tlog.granule%TYPE DEFAULT NULL,
          pstartend   IN tlog.startend%TYPE DEFAULT NULL,
          pcall           IN tlog.who_call%TYPE DEFAULT g_who_call,
          pp1             IN tlog.p1%TYPE DEFAULT NULL,
          pp2             IN tlog.p2%TYPE DEFAULT NULL
        )
        IS
        BEGIN
                INSERT INTO tlog
                    (
                     ID         ,
                     ldate      ,
                     lhsecs     ,
                     llevel     ,
                     lsection   ,
                     luser      ,
                     ltexte     ,
                     piece      ,
                     granule    ,
                     startend   ,
                     who_call   ,
                     p1         ,
                     p2         
                     ) VALUES (
                     pid,
                     pldate,
                     plhsecs,
                     pllevel,
                     plsection,
                     pluser,
                     pltexte,
                     g_session_id,
                     pgranule,
                     pstartend,
                     pcall,
                     pp1,
                     pp2
                    );
        END;
        
        --------------------------------------------------------------------
        PROCEDURE addrowautonomous
        (
          pid         IN tlog.ID%TYPE,
          pldate      IN tlog.ldate%TYPE,
          plhsecs     IN tlog.lhsecs%TYPE,
          pllevel     IN tlog.llevel%TYPE,
          plsection   IN tlog.lsection%TYPE,
          pluser      IN tlog.luser%TYPE,
          pltexte     IN tlog.ltexte%TYPE,
          pgranule    IN tlog.granule%TYPE DEFAULT NULL,
          pstartend   IN tlog.startend%TYPE DEFAULT NULL,
          pcall           IN tlog.who_call%TYPE DEFAULT g_who_call,
          pp1             IN tlog.p1%TYPE DEFAULT NULL,
          pp2             IN tlog.p2%TYPE DEFAULT NULL
        )
        IS
        PRAGMA autonomous_transaction;
        BEGIN
         addrow
          (
           pid         => pid,
           pldate      => pldate,
           plhsecs     => plhsecs,
           pllevel     => pllevel,
           plsection   => plsection,
           pluser      => pluser,
           pltexte     => pltexte,
           pgranule    => pgranule,
           pstartend   => pstartend,
           pcall       => pcall,
           pp1         => pp1,
           pp2         => pp2
          );
          COMMIT;
          EXCEPTION WHEN OTHERS THEN
              ERROR;
              ROLLBACK;
              RAISE;
        END;
        
        --//------------------------------------------------------------------
        
        FUNCTION getlevel
        (
            pctx       IN log_ctx
        )
        RETURN tlog.llevel%TYPE
        IS
        BEGIN
            RETURN pctx.llevel;
        END getlevel;
        
        --//------------------------------------------------------------------
        
        FUNCTION init
        (
            psection        IN tlog.lsection%TYPE DEFAULT NULL ,
            plevel          IN tlog.llevel%TYPE   DEFAULT ldebug   ,
            plogtable       IN BOOLEAN            DEFAULT TRUE,
            pout_trans      IN BOOLEAN            DEFAULT TRUE,
            pcall           IN tlog.who_call%TYPE DEFAULT g_who_call,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        )
        RETURN log_ctx
        IS
            pctx       log_ctx;
        BEGIN
        
            pctx.isdefaultinit   := TRUE;
            pctx.lsection        := nvl(psection, which_object_call(9,'ALL'));
            pctx.init_lsection   := psection;
            pctx.llevel          := plevel;
            pctx.init_llevel     := plevel;
            pctx.use_out_trans   := pout_trans;
            pctx.use_logtable    := plogtable;
            pctx.who_call        := pcall;
            pctx.p1              := pp1;
            pctx.p2              := pp2;
        
            RETURN pctx;
        END init;
        
        --//------------------------------------------------------------------
        
        FUNCTION getdefaultcontext
        RETURN log_ctx
        IS
            newctx      log_ctx;
            lsection    tlog.lsection%TYPE;
        BEGIN
            --lSECTION := calleurname;
            newctx := init (psection => lsection);
            RETURN newctx;
        END getdefaultcontext;
        
        --//------------------------------------------------------------------
        
        FUNCTION getlevel
        RETURN tlog.llevel%TYPE
        IS
            generiquectx log_ctx := getdefaultcontext;
        BEGIN
            RETURN getlevel( pctx => generiquectx);
        END getlevel;
        
        --//------------------------------------------------------------------
        
        FUNCTION getnextid RETURN tlog.ID%TYPE
        IS
            temp NUMBER;
        BEGIN
             SELECT slog.NEXTVAL INTO temp FROM dual;
             RETURN temp;
        
        END getnextid;
        
        --//------------------------------------------------------------------
        
        PROCEDURE     checkandinitctx(
            pctx        IN OUT NOCOPY log_ctx
        )
        IS
            lsection    tlog.lsection%TYPE;
        BEGIN
            IF pctx.isdefaultinit = FALSE THEN
                --lSECTION := calleurname;
                pctx := init (psection => lsection);
            END IF;
        END;
        
        --//------------------------------------------------------------------
        
        FUNCTION gettextinlevel (
            pcode tloglevel.lcode%TYPE
        ) RETURN  tlog.llevel%TYPE
        IS
            ret tlog.llevel%TYPE ;
        BEGIN
        
            SELECT llevel INTO ret
            FROM tloglevel
            WHERE lcode = pcode;
            RETURN ret;
        EXCEPTION
            WHEN OTHERS THEN
                RETURN ldebug;
        END gettextinlevel;
        
        --//------------------------------------------------------------------
        
        FUNCTION getsection
        (
            pctx        IN OUT NOCOPY log_ctx
        )
        RETURN tlog.lsection%TYPE
        IS
        BEGIN
        
            RETURN pctx.lsection;
        
        END getsection;
        
        --//------------------------------------------------------------------
        
        FUNCTION islevelenabled
        (
            pctx        IN   log_ctx,
            plevel       IN tlog.llevel%TYPE
        )
        RETURN BOOLEAN
        IS
        BEGIN
            IF getlevel(pctx) >= plevel THEN
                RETURN TRUE;
            ELSE
                RETURN FALSE;
            END IF;
        END islevelenabled;
        
        --//------------------------------------------------------------------
        
        PROCEDURE assert (
            pctx                     IN OUT NOCOPY log_ctx                        ,
            pcondition               IN BOOLEAN                                   ,
            plogerrormessageiffalse  IN VARCHAR2 DEFAULT 'assert condition error' ,
            plogerrorcodeiffalse     IN NUMBER   DEFAULT -20000                   ,
            praiseexceptioniffalse   IN BOOLEAN  DEFAULT FALSE                    ,
            plogerrorreplaceerror    IN BOOLEAN  DEFAULT FALSE
        )
        IS
        BEGIN
          checkandinitctx(pctx);
          IF NOT islevelenabled(pctx, ldebug) THEN
                RETURN;
          END IF;
        
          IF NOT pcondition THEN
             LOG (plevel => ldebug, pctx => pctx,  ptexte => 'AAS'||plogerrorcodeiffalse||': '||plogerrormessageiffalse);
             IF praiseexceptioniffalse THEN
                raise_application_error(plogerrorcodeiffalse, plogerrormessageiffalse, plogerrorreplaceerror);
             END IF;
          END IF;
        END assert;
        
        --//------------------------------------------------------------------
        
        PROCEDURE LOG
        (
            pctx        IN OUT NOCOPY log_ctx                      ,
            pid         IN       tlog.ID%TYPE                      ,
            pldate      IN       tlog.ldate%TYPE                   ,
            plhsecs     IN       tlog.lhsecs%TYPE                  ,
            pllevel     IN       tlog.llevel%TYPE                  ,
            plsection   IN       tlog.lsection%TYPE                ,
            pluser      IN       tlog.luser%TYPE                   ,
            pltexte     IN       tlog.ltexte%TYPE                  ,
            pgranule    IN       tlog.granule%TYPE DEFAULT NULL    ,
            pstartend   IN       tlog.startend%TYPE DEFAULT NULL   ,
            pcall           IN tlog.who_call%TYPE DEFAULT g_who_call,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        )
        IS
            ret NUMBER;
            lltexte tlog.ltexte%TYPE ;
            pt NUMBER;
        BEGIN
        
            IF pctx.isdefaultinit = FALSE THEN
                ERROR('please is necessary to use plog.init for yours contexte.');
            END IF;
        
            IF pltexte IS NULL THEN
                lltexte := 'SQLCODE:'||SQLCODE ||' SQLERRM:'||sqlerrm;
            ELSE
                BEGIN
                    lltexte := pltexte;
                EXCEPTION
                    WHEN value_error THEN
                        assert (pctx, LENGTH(pltexte) <= 2000, 'Log Message id:'||pid||' too long. ');
                        lltexte := substr(pltexte, 0, 2000);
                    WHEN OTHERS THEN NULL;
                        fatal;
                END;
        
            END IF;
        
            IF pctx.use_logtable = TRUE THEN
        
                IF pctx.use_out_trans = FALSE THEN
                         addrow
                          (
                           pid         => pid,
                           pldate      => pldate,
                           plhsecs     => plhsecs,
                           pllevel     => pllevel,
                           plsection   => plsection,
                           pluser      => pluser,
                           pltexte     => lltexte,
                           pgranule    => pgranule,
                           pstartend   => pstartend,
                           pcall       => pcall,
                   pp1         => pp1,
                           pp2         => pp2
                          );
                ELSE
                         addrowautonomous
                          (
                           pid         => pid,
                           pldate      => pldate,
                           plhsecs     => plhsecs,
                           pllevel     => pllevel,
                           plsection   => plsection,
                           pluser      => pluser,
                           pltexte     => lltexte,
                           pgranule    =>pgranule,
                           pstartend   => pstartend,
                           pcall       => pcall,
                   pp1         => pp1,
                           pp2         => pp2
                          );
                END IF;
            END IF;
        
        END LOG;
        
        --------------------------------------------------------------------
        PROCEDURE LOG
        (
            pctx        IN OUT NOCOPY log_ctx                      ,
            plevel      IN tlog.llevel%TYPE                        ,
            ptexte      IN tlog.ltexte%TYPE DEFAULT defaultextmess ,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        
             lid        tlog.ID%TYPE        ;
             llsection  tlog.lsection%TYPE  := getsection(pctx);
             llhsecs    tlog.lhsecs%TYPE                       ;
             M VARCHAR2(100);
        
        BEGIN
            checkandinitctx(pctx);
            IF plevel > getlevel(pctx) THEN
                RETURN;
            END IF;
            lid := getnextid;
        
            dbms_application_info.set_module(substr(llsection,1,30)||'['||to_char(pgranule)||']'||'['||to_char(sysdate,'HH24:MI:SS')||']'
             ,substr(g_who_call||'['||to_char(lid)||']',1,30));
            --select HSECS into lLHSECS from V$TIMER;
        
        
            LOG (   pctx        =>pctx,
                    pid         =>lid,
                    pldate      =>sysdate,
                    plhsecs     =>llhsecs,
                    pllevel     =>plevel,
                    plsection   =>llsection,
                    pluser      =>USER,
                    pltexte     =>ptexte,
                    pgranule     =>pgranule,
                    pstartend   =>pstartend,
                    pp1         =>pp1,
                    pp2         =>pp2
                );
        
        END LOG;
        
        --//------------------------------------------------------------------
        PROCEDURE LOG
        (
            plevel      IN tlog.llevel%TYPE                        ,
            ptexte      IN tlog.ltexte%TYPE DEFAULT defaultextmess,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
           generiquectx log_ctx := getdefaultcontext;
        BEGIN
            LOG(plevel => plevel, pctx => generiquectx, ptexte => ptexte,pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2);
        END LOG;
        
        --//------------------------------------------------------------------
        PROCEDURE DEBUG
        (
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('DEBUG'), ptexte => ptexte, pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2);
        END DEBUG;
        
        --//------------------------------------------------------------------
        PROCEDURE DEBUG
        (
            pctx        IN OUT NOCOPY log_ctx                      ,
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('DEBUG'), pctx => pctx, ptexte => ptexte, pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2);
        END DEBUG;
        
        --//------------------------------------------------------------------
        PROCEDURE info
        (
            pctx        IN OUT NOCOPY log_ctx                      ,
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('INFO'), pctx => pctx,  ptexte => ptexte, pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2);
        END info;
        
        PROCEDURE info
        (
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('INFO'),  ptexte => ptexte, pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2 );
        END info;
        
        --//------------------------------------------------------------------
        PROCEDURE warn
        (
            pctx        IN OUT NOCOPY log_ctx                      ,
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL   ,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('WARN'), pctx => pctx,  ptexte => ptexte,pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2 );
        END warn;
        PROCEDURE warn
        (
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL ,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('WARN'),  ptexte => ptexte, pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2);
        END warn;
        
        --//------------------------------------------------------------------
        PROCEDURE ERROR
        (
            pctx        IN OUT NOCOPY log_ctx,
            ptexte      IN tlog.ltexte%TYPE  DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('ERROR'), pctx => pctx,  ptexte => ptexte, pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2);
        END ERROR;
        PROCEDURE ERROR
        (
            ptexte      IN tlog.ltexte%TYPE  DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('ERROR'),  ptexte => ptexte, pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2);
        END ERROR;
        
        --//------------------------------------------------------------------
        
        PROCEDURE fatal
        (
            pctx        IN OUT NOCOPY log_ctx,
            ptexte      IN tlog.ltexte%TYPE  DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('FATAL'), pctx => pctx,  ptexte => ptexte, pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2);
        END fatal;
        
        PROCEDURE fatal
        (
            ptexte      IN tlog.ltexte%TYPE DEFAULT NULL,
            pgranule    IN tlog.granule%TYPE DEFAULT NULL,
            pstartend   IN tlog.startend%TYPE DEFAULT NULL,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        ) IS
        BEGIN
            LOG(plevel => gettextinlevel('FATAL'),  ptexte => ptexte, pgranule=>pgranule,
            pstartend=>pstartend, pp1=>pp1, pp2=>pp2);
        END fatal;
        
        --//------------------------------------------------------------------
        
        PROCEDURE log_in_cursor
        (
            p_step IN OUT NUMBER,
            p_date IN OUT DATE,
            p_granule IN NUMBER,
            pp1             IN tlog.p1%TYPE DEFAULT NULL,
            pp2             IN tlog.p2%TYPE DEFAULT NULL
        )
        IS
            v_action VARCHAR2(30);
        BEGIN
        
            IF p_step=0 THEN p_date:=sysdate; END IF;
        
            p_step:=p_step+1;
            
            v_action:=substr(g_who_call,1,12)||'['||to_char(p_step)||'L/'|| to_char(round((sysdate-p_date)*24*60*60))||'S]';
            
            dbms_application_info.set_module(substr(which_object_call(6,'ALL'),1,30)||'['||to_char(p_granule)||']'||'['||to_char(p_date,'HH24:MI:SS')||']',v_action);
            
        END;
        
        --//------------------------------------------------------------------
        
        PROCEDURE rs_start
        IS
        BEGIN
            DELETE FROM run_stats;
            
            INSERT INTO run_stats
            SELECT 'before', v_stats.* FROM v_stats;
            
            g_start := dbms_utility.get_time;
        END;
        
        --//------------------------------------------------------------------
        
        PROCEDURE rs_middle
        IS
        BEGIN
            g_run1 := (dbms_utility.get_time-g_start);
        
            INSERT INTO run_stats
            SELECT 'after 1', v_stats.* FROM v_stats;
            g_start := dbms_utility.get_time;
        
        END;
        
        --//------------------------------------------------------------------
        
        PROCEDURE rs_stop(p_difference_threshold IN NUMBER DEFAULT 0)
        IS
        BEGIN
            g_run2 := (dbms_utility.get_time-g_start);
        
            dbms_output.put_line ( 'Run1 ran in ' || g_run1 || ' hsecs' );
            dbms_output.put_line ( 'Run2 ran in ' || g_run2 || ' hsecs' );
            dbms_output.put_line ( 'run 1 ran in ' || round(g_run1/g_run2*100,2) || '% of the time' );
            dbms_output.put_line ( CHR(9) );
        
            INSERT INTO run_stats
            SELECT 'after 2', v_stats.* FROM v_stats;
        
            dbms_output.put_line
            ( rpad( 'Name', 30 ) || lpad( 'Run1', 10 ) ||
              lpad( 'Run2', 10 ) || lpad( 'Diff', 10 ) );
        
            FOR x IN
            ( SELECT rpad( A.NAME, 30 ) ||
                     to_char( b.VALUE-A.VALUE, '9,999,999' ) ||
                     to_char( C.VALUE-b.VALUE, '9,999,999' ) ||
                     to_char( ( (C.VALUE-b.VALUE)-(b.VALUE-A.VALUE)), '9,999,999' ) DATA
                FROM run_stats A, run_stats b, run_stats C
               WHERE A.NAME = b.NAME
                 AND b.NAME = C.NAME
                 AND A.runid = 'before'
                 AND b.runid = 'after 1'
                 AND C.runid = 'after 2'
                 AND (C.VALUE-A.VALUE) > 0
                 AND ABS( (C.VALUE-b.VALUE) - (b.VALUE-A.VALUE) )
                       > p_difference_threshold
               ORDER BY ABS( (C.VALUE-b.VALUE)-(b.VALUE-A.VALUE))
            ) LOOP
                dbms_output.put_line( x.DATA );
            END LOOP;
        
            dbms_output.put_line( CHR(9) );
            dbms_output.put_line
            ( 'Run1 latches total versus runs -- difference and pct' );
            dbms_output.put_line
            ( lpad( 'Run1', 10 ) || lpad( 'Run2', 10 ) ||
              lpad( 'Diff', 10 ) || lpad( 'Pct', 8 ) );
        
            FOR x IN
            ( SELECT to_char( run1, '9,999,999' ) ||
                     to_char( run2, '9,999,999' ) ||
                     to_char( diff, '9,999,999' ) ||
                     to_char( round( run1/run2*100,2 ), '999.99' ) || '%' DATA
                FROM ( SELECT SUM(b.VALUE-A.VALUE) run1, SUM(C.VALUE-b.VALUE) run2,
                              SUM( (C.VALUE-b.VALUE)-(b.VALUE-A.VALUE)) diff
                         FROM run_stats A, run_stats b, run_stats C
                        WHERE A.NAME = b.NAME
                          AND b.NAME = C.NAME
                          AND A.runid = 'before'
                          AND b.runid = 'after 1'
                          AND C.runid = 'after 2'
                          AND A.NAME LIKE 'LATCH%'
                        )
            ) LOOP
                dbms_output.put_line( x.DATA );
            END LOOP;
        END;
        
        --//------------------------------------------------------------------
        
        FUNCTION get_process_name(p_id IN procedures_def.idprocedure%TYPE,
          p_name_default IN procedures_def.NAME%TYPE DEFAULT 'UNKNOWN')
        RETURN procedures_def.NAME%TYPE
        IS
         
         v_result procedures_def.NAME%TYPE;
        
        BEGIN
        
         SELECT UPPER(NAME) INTO v_result FROM procedures_def WHERE idprocedure=p_id;
         RETURN v_result;
        
        EXCEPTION
         WHEN OTHERS THEN RETURN p_name_default;
        END;
    
    --// Main part
    
    BEGIN
      g_session_id := userenv('SESSIONID');
    END detralog;
    /

/***********************************************/
/* SYNONYMS - Watcher                          */
/***********************************************/

    CREATE PUBLIC SYNONYM detralog FOR watcher.detralog;
    GRANT EXECUTE ON detralog TO PUBLIC;
    
    CREATE OR REPLACE VIEW v_tlog AS
    SELECT * FROM tlog WHERE UPPER(luser)=USER
    WITH CHECK OPTION;
    
    CREATE PUBLIC SYNONYM event_logs FOR v_tlog;
    GRANT SELECT ON v_tlog TO PUBLIC;
    
    CREATE OR REPLACE VIEW v_procedures_def AS
    SELECT * FROM procedures_def WHERE UPPER(username)=USER
    WITH CHECK OPTION;
    
    CREATE PUBLIC SYNONYM procedures_defs FOR v_procedures_def;
    GRANT SELECT,INSERT,DELETE,UPDATE ON v_procedures_def TO PUBLIC;
    
    CREATE PUBLIC SYNONYM v_show_report_all FOR v_show_report_all;
    GRANT SELECT ON v_show_report_all TO PUBLIC;


/***********************************************/
/* TRIGGER - Watcher                           */
/***********************************************/
    CREATE OR REPLACE TRIGGER biu_fer_debugtab
    BEFORE INSERT OR UPDATE ON debugtab FOR EACH ROW
    BEGIN
      :NEW.modules := UPPER( :NEW.modules );
      :NEW.show_date := UPPER( :NEW.show_date );
      :NEW.session_id := UPPER( :NEW.session_id );
      :NEW.userid := UPPER( :NEW.userid );
      :NEW.sub_module:=UPPER( :NEW.sub_module );
    
      DECLARE
        l_date VARCHAR2(100);
      BEGIN
        l_date := to_char( sysdate, :NEW.DATE_FORMAT );
      EXCEPTION
        WHEN OTHERS THEN
          raise_application_error( -20001, 'Invalid Date Format In Debug Date Format' );
      END;
    END;
    /

/***********************************************/
/* PROCEDURES - Watcher                        */
/***********************************************/
    CREATE OR REPLACE PROCEDURE want_to_trace
    AS
    
    BEGIN
        detralog.init('_test');
        
        FOR I IN 1 .. 10 LOOP
            detralog.F( 'processing step %s of %s', I,10 );
            dbms_lock.sleep(1);
        END LOOP;
        
        detralog.CLEAR;
    END;
    
    CREATE OR REPLACE PROCEDURE want_to_log
    AS
        -- control variables
         v_step NUMBER;
         v_date DATE;
         v_idprocedure procedures_def.idprocedure%TYPE:=2;
        -- local variables
         v_id NUMBER;
    BEGIN
    
        detralog.info('Starting...',v_idprocedure,detralog.tlog_start);
        v_step:=0;
        
        FOR I IN 1 .. 10 LOOP
            detralog.log_in_cursor(v_step,v_date,v_idprocedure);
            dbms_lock.sleep(2);
        END LOOP;
    
        detralog.info(v_step||'/'||round((sysdate-v_date)*24*60*60),v_idprocedure,detralog.tlog_cursor);
    
        SELECT ID INTO v_id FROM tlog WHERE ID=-1;
        detralog.info('Ending...',v_idprocedure,detralog.tlog_end);
        
    EXCEPTION
        WHEN OTHERS THEN 
            detralog.fatal(pgranule=>v_idprocedure,pstartend=>detralog.tlog_end);
    END;
 
/************************************************************************** 
    Moduri de folosire
    -------------------------------------------
    DECLARE   
        v_alloc_id NUMBER:=234;
        v_who VARCHAR2(100):=detralog.get_process_name(v_alloc_id);
    BEGIN
        detralog.info('STARTING...',pgranule=>v_alloc_id);
    
        detralog.info('ENDING...',pgranule=>v_alloc_id);
    EXCEPTION
        WHEN OTHERS THEN
        detralog.fatal(pgranule=>v_alloc_id,pstartend=>detralog.tlog_end);
    END;
*****************************************************************************/