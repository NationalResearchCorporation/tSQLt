IF OBJECT_ID('tSQLt.Private_CreateProcedureSpy') IS NOT NULL DROP PROCEDURE tSQLt.Private_CreateProcedureSpy;
GO
---Build+
CREATE PROCEDURE [tSQLt].[Private_CreateProcedureSpy]
    @ProcedureObjectId INT,
    @OriginalProcedureName NVARCHAR(MAX),
    @LogTableName NVARCHAR(MAX),
    @CommandToExecute NVARCHAR(MAX) = NULL
AS
BEGIN
    DECLARE @Cmd NVARCHAR(MAX);
    DECLARE @ProcParmList NVARCHAR(MAX),
            @TableColList NVARCHAR(MAX),
            @ProcParmTypeList NVARCHAR(MAX),
            @TableColTypeList NVARCHAR(MAX);
            
    DECLARE @Seperator CHAR(1),
            @ProcParmTypeListSeparater CHAR(1),
            @ParamName sysname,
            @TypeName sysname,
            @IsOutput BIT,
            @IsCursorRef BIT;
           
    SELECT @Seperator = '', @ProcParmTypeListSeparater = '', 
           @ProcParmList = '', @TableColList = '', @ProcParmTypeList = '', @TableColTypeList = '';
      
    DECLARE Parameters CURSOR FOR
     SELECT p.name, t.TypeName, is_output, is_cursor_ref
       FROM sys.parameters p
       CROSS APPLY tSQLt.Private_GetFullTypeName(p.user_type_id,p.max_length,p.precision,p.scale,NULL) t
      WHERE object_id = @ProcedureObjectId;
    
    OPEN Parameters;
    
    FETCH NEXT FROM Parameters INTO @ParamName, @TypeName, @IsOutput, @IsCursorRef;
    WHILE (@@FETCH_STATUS = 0)
    BEGIN
        IF @IsCursorRef = 0
        BEGIN
         DECLARE @ParmIsTableType BIT = 0;
         IF (@ParamName IN (SELECT DISTINCT p.NAME
                        FROM sys.parameters p
                        JOIN sys.types t ON   p.system_type_id = t.system_type_id
                        WHERE t.is_table_type = 1))
         BEGIN
            SET @ParmIsTableType = 1
         END

         IF @ParmIsTableType = 1
             BEGIN
                SELECT @ProcParmList = @ProcParmList + @Seperator + '(SELECT * FROM ' + @ParamName + ' FOR XML AUTO)', 
                       @ProcParmTypeList = @ProcParmTypeList + @ProcParmTypeListSeparater + @ParamName + ' ' + @TypeName + 
                                           CASE WHEN @IsOutput = 1 THEN ' OUT' 
                                                ELSE '' 
                                           END + ' READONLY'
             END
         ELSE
             BEGIN
                SELECT @ProcParmList = @ProcParmList + @Seperator + @ParamName, 
                       @ProcParmTypeList = @ProcParmTypeList + @ProcParmTypeListSeparater + @ParamName + ' ' + @TypeName + ' = NULL ' + 
                                           CASE WHEN @IsOutput = 1 THEN ' OUT' 
                                                ELSE '' 
                                           END
             END

            SELECT @TableColList = @TableColList + @Seperator + '[' + STUFF(@ParamName,1,1,'') + ']', 
                   @TableColTypeList = @TableColTypeList + ',[' + STUFF(@ParamName,1,1,'') + '] ' + 
                          CASE WHEN @TypeName LIKE '%nchar%'
                                 OR @TypeName LIKE '%nvarchar%' THEN 'nvarchar(MAX)'
                               WHEN @TypeName LIKE '%char%' THEN 'varchar(MAX)'
                               WHEN @ParmIsTableType = 1 THEN 'XML'
                               ELSE @TypeName
                          END + ' NULL';

            SELECT @Seperator = ',';        
            SELECT @ProcParmTypeListSeparater = ',';
        END
        ELSE
        BEGIN
            SELECT @ProcParmTypeList = @ProcParmTypeListSeparater + @ParamName + ' CURSOR VARYING OUTPUT';
            SELECT @ProcParmTypeListSeparater = ',';
        END;
        
        FETCH NEXT FROM Parameters INTO @ParamName, @TypeName, @IsOutput, @IsCursorRef;
    END;
    
    CLOSE Parameters;
    DEALLOCATE Parameters;
    
    DECLARE @InsertStmt NVARCHAR(MAX);
    SELECT @InsertStmt = 'INSERT INTO ' + @LogTableName + 
                         CASE WHEN @TableColList = '' THEN ' DEFAULT VALUES'
                              ELSE ' (' + @TableColList + ') SELECT ' + @ProcParmList
                         END + ';';
                         
    SELECT @Cmd = 'CREATE TABLE ' + @LogTableName + ' (_id_ int IDENTITY(1,1) PRIMARY KEY CLUSTERED ' + @TableColTypeList + ');';
    EXEC(@Cmd);

    SELECT @Cmd = 'CREATE PROCEDURE ' + @OriginalProcedureName + ' ' + @ProcParmTypeList + 
                  ' AS BEGIN ' + 
                     @InsertStmt + 
                     ISNULL(@CommandToExecute, '') + ';' +
                  ' END;';
    EXEC(@Cmd);

    RETURN 0;
END;
---Build-
GO
