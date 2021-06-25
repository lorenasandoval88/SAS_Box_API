/* My path is different for UNIX vs Windows */
%let authpath = %sysfunc(ifc(&SYSSCP. = WIN,
/* Save creds file in your user root folder ie. C:\Users\sandovall2 */
	 C:\Users\&sysuserid.\Downloads, 
	 /u/&sysuserid.\Downloads));
 
/* This should be a file that only YOU or trusted group members can read */
/* Use "chmod 0600 filename" in UNIX environment */
/* "dotfile" notation is convention for on UNIX for "hidden" */
filename auth "&authpath./epiboxCredentials.csv"; 
 
/* Read in the secret account keys from epiboxCredentials.csv */
/* get credentials file from https://episphere.github.io/epibox */

data temp;
 infile auth firstobs=2 dsd dlm=',';
 length client_id $ 100 client_secret $ 100 refresh_token $ 100;
 input client_id client_secret refresh_token;
 call symputx('client_id',client_id);
 call symputx('client_secret',client_secret);
 call symputx('refresh_token',refresh_token);
run;

/* Box API call to get a new access token, valid for one hour, saved as accessToken.json*/
%let oauth2 = https://api.box.com/oauth2/token;
%let ct = application/x-www-form-urlencoded;
filename outfile "&authpath./accessToken.json";

proc http
    method = "POST"
    url="&oauth2"
    in = "client_id=&client_id.%str(&)client_secret=&client_secret.%str(&)grant_type=refresh_token%str(&)refresh_token=&refresh_token"
    ct = "application/x-www-form-urlencoded"
    out=outfile;
 run; 
/*--------------------------------------------------------------------------------------------------------------------*/
 /* get variables from access token api call, see https://blogs.sas.com/content/sgf/2020/07/30/curl-to-proc-http. 
 /*File is in jsonl format, converting to json fomrat below and saving as accessToken2.json*/
/* define access_token and refresh token variable */
filename jsonfile "&authpath./accessToken2.json";
libname test json fileref=jsonfile;
data _null_;
  file jsonfile ;
  infile outfile end=eof ;
  if _n_=1 then put '[';
  if eof then put ']';
  input ;
  put _infile_ @;
  if not eof then put ',';
  else put;
   set test.root;
 call symputx("access_token",access_token);
 call symputx("refresh_token",refresh_token);
run;

/*---------------------------------------------------------------------------------------*/
/*FINALLY........get the box file using the access_token saved in a macro variable*/
/* make response file to save box file*/
filename  respnse "&authpath./response_data.csv" ;
 proc http
      url= 'https://api.box.com/2.0/files/794666553027/content' 
        method    = "GET"
        out       = respnse;
    headers      "Authorization"  = "Bearer &access_token"; 
 run;


 /* UPLOAD LOCAL FILE TO BOX**********************************************************************************************************/
/* provide a folder id and file name. Getting 409 conflict error when uploading existing file. 
 Not able to overwrite yet, only create new  */
 filename copyfile "C:\Users\sandovall2\Downloads\test1.txt" ;

filename request TEMP ;
%let boundary=foobar;
%let boxfolderID=133596945131;
%let updestfile=upload3.txt;

filename resptext temp;
filename resphdrs temp;

*box.com upload require json two parts for multipart/form-data;

data _null_;
    file request termstr=CRLF;
    if _n_ = 1 then do;
        put "--&boundary";
        put 'Content-Disposition: form-data; name="attributes"';
        put ;
        put '{"name":"' "&updestfile" '", "parent":{"id":"' "&boxfolderID" '"}}';
        put "--&boundary";
        put 'Content-Disposition: form-data; name="file"; filename="' "&updestfile" '"';
        put "Content-Type: application/vnd.ms-excel";
        /*put "Content-Type: application/octet-stream";*/

       put ;
      end;
run;
data _null_;  
    file request mod recfm=n;
    infile copyfile recfm=n;
    input c $CHAR1.;
    put c $CHAR1. @@;
run;

data _null_;
    file request mod termstr=CRLF;
    put "--&boundary--";
run;

data _null_;
    length bytes $1024;
    fid = fopen("request");
    rc = fread(fid);
    bytes = finfo(fid, 'File Size (bytes)');
    call symput("FileSize",trim(bytes));
    rc = fclose(fid);
    put bytes;
  run;
 proc http /* use different api, upload new version*/
      url="https://upload.box.com/api/2.0/files/content"
        method    = "POST"
        out       = resptext
        headerout = resphdrs
        in        = request
        ct        = "multipart/form-data; boundary=&boundary;Content-Length=&filesize;Content-MD5"   ;
    headers      "Authorization"  = "Bearer &access_token"    ;
 run;
