function conn = smp_sql_connect(target)
% SMP_SQL_CONNECT  Establish a JDBC connection to the target SQL database.
%
% Usage:
%   conn = smp_sql_connect('azure_local')   % local SQL Express
%   conn = smp_sql_connect('azure_online')  % Motorsport Azure SQL (MFA popup on first use)
%
% Inputs:
%   target  - string: 'azure_local' | 'azure_online'
%
% Output:
%   conn    - java.sql.Connection object — pass to smp_push_to_sql
%             Call conn.close() when done with the session.
%
% Notes:
%   - azure_online uses ActiveDirectoryInteractive (Entra ID MFA).
%     A browser window will pop on the first call per MATLAB session.
%     Subsequent calls in the same session are silent (token cached).
%   - azure_local uses Windows Authentication (Trusted_Connection).
%     No popup, no credentials needed.
%   - Call once per MATLAB session and reuse the connection object.
%
% =========================================================

    % ── JDBC driver paths ─────────────────────────────────────────────────
    JDBC_DIR  = 'C:\SimEnv\dataAcquisition\serverInteraction\sqljdbc\enu\jars';
    AUTH_DLL  = 'C:\SimEnv\dataAcquisition\serverInteraction\sqljdbc\enu\auth\x64';

    JAR_MAIN  = fullfile(JDBC_DIR, 'mssql-jdbc-13.4.0.jre8.jar');
    JAR_MSAL  = fullfile(JDBC_DIR, 'msal4j-1.24.0.jar');

    % ── Credentials — fill in your values ────────────────────────────────
    %  azure_online
    AZ_SERVER    = 'sc-sql-data.database.windows.net';
    AZ_DATABASE  = 'motorsport-sql-data';
    AZ_TENANT_ID = '43f9227d-3dd6-4a9e-8ffd-2bd4a184889a';

    %  azure_local  (SQL Express — Windows Auth, no credentials needed)
    LOCAL_SERVER   = 'localhost\SQLEXPRESS';
    LOCAL_DATABASE = 'motorsport_local';

    % ── Load JDBC drivers onto Java classpath ────────────────────────────
    % ── Verify JDBC driver is on classpath ───────────────────────────────
    static_cp = javaclasspath('-static');
    if ~any(contains(static_cp, 'mssql-jdbc'))
        error(['smp_sql_connect: JDBC driver not found on static classpath.\n' ...
               'Add the following lines to javaclasspath.txt (run: edit(fullfile(prefdir,''javaclasspath.txt'')))\n' ...
               '  %s\n  %s\n' ...
               'Then restart MATLAB.'], JAR_MAIN, JAR_MSAL);
    end

    % ── Register driver ───────────────────────────────────────────────────
    try
        driver = com.microsoft.sqlserver.jdbc.SQLServerDriver;
        java.sql.DriverManager.registerDriver(driver);
    catch ME
        error('smp_sql_connect: Failed to register SQL Server JDBC driver.\n%s', ME.message);
    end

    % ── Build connection string and connect ───────────────────────────────
    switch lower(target)

        case 'azure_local'
            % Windows Integrated Auth — uses your AVESCO\lholliday login
            conn_str = sprintf( ...
                'jdbc:sqlserver://%s;databaseName=%s;integratedSecurity=true;', ...
                LOCAL_SERVER, LOCAL_DATABASE);
            fprintf('Connecting to LOCAL SQL Express (%s / %s)...\n', ...
                LOCAL_SERVER, LOCAL_DATABASE);
            try
                conn = java.sql.DriverManager.getConnection(conn_str);
            catch ME
                error(['smp_sql_connect: Could not connect to local SQL Express.\n' ...
                       'Check that SQL Express is running and database "%s" exists.\n' ...
                       'Error: %s'], LOCAL_DATABASE, ME.message);
            end

        case 'azure_online'
            % Entra ID Interactive — browser MFA popup on first use per session
            conn_str = sprintf( ...
                ['jdbc:sqlserver://%s;databaseName=%s;' ...
                 'authentication=ActiveDirectoryInteractive;' ...
                 'tenantId=%s;encrypt=true;trustServerCertificate=false;' ...
                 'hostNameInCertificate=*.database.windows.net;loginTimeout=60;'], ...
                AZ_SERVER, AZ_DATABASE, AZ_TENANT_ID);
            fprintf('Connecting to Azure SQL (%s / %s)...\n', AZ_SERVER, AZ_DATABASE);
            fprintf('  >> A browser window may appear for MFA authentication.\n');
            try
                conn = java.sql.DriverManager.getConnection(conn_str);
            catch ME
                error(['smp_sql_connect: Could not connect to Azure SQL.\n' ...
                       'Check server name, database name, and tenant ID.\n' ...
                       'Error: %s'], ME.message);
            end

        otherwise
            error('smp_sql_connect: Unknown target "%s". Use ''azure_local'' or ''azure_online''.', target);
    end

    fprintf('Connected successfully to [%s].\n', upper(target));
    fprintf('Call conn.close() when done with this session.\n\n');
end
