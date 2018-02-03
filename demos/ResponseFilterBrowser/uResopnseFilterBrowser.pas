// ************************************************************************
// ***************************** CEF4Delphi *******************************
// ************************************************************************
//
// CEF4Delphi is based on DCEF3 which uses CEF3 to embed a chromium-based
// browser in Delphi applications.
//
// The original license of DCEF3 still applies to CEF4Delphi.
//
// For more information about CEF4Delphi visit :
//         https://www.briskbard.com/index.php?lang=en&pageid=cef
//
//        Copyright � 2018 Salvador D�az Fau. All rights reserved.
//
// ************************************************************************
// ************ vvvv Original license and comments below vvvv *************
// ************************************************************************
(*
 *                       Delphi Chromium Embedded 3
 *
 * Usage allowed under the restrictions of the Lesser GNU General Public License
 * or alternatively the restrictions of the Mozilla Public License 1.1
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
 * the specific language governing rights and limitations under the License.
 *
 * Unit owner : Henri Gourvest <hgourvest@gmail.com>
 * Web site   : http://www.progdigy.com
 * Repository : http://code.google.com/p/delphichromiumembedded/
 * Group      : http://groups.google.com/group/delphichromiumembedded
 *
 * Embarcadero Technologies, Inc is not permitted to use or redistribute
 * this source code without explicit permission.
 *
 *)

unit uResopnseFilterBrowser;

{$I cef.inc}

interface

uses
  {$IFDEF DELPHI16_UP}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, System.SyncObjs,
  {$ELSE}
  Windows, Messages, SysUtils, Variants, Classes, Graphics,
  Controls, Forms, Dialogs, StdCtrls, ExtCtrls, SyncObjs,
  {$ENDIF}
  uCEFChromium, uCEFWindowParent, uCEFInterfaces, uCEFConstants, uCEFTypes, uCEFResponseFilter;

const
  STREAM_COPY_COMPLETE    = WM_APP + $B00;

type
  TResponseFilterBrowserFrm = class(TForm)
    AddressPnl: TPanel;
    AddressEdt: TEdit;
    GoBtn: TButton;
    Timer1: TTimer;
    Chromium1: TChromium;
    CEFWindowParent1: TCEFWindowParent;
    Splitter1: TSplitter;
    Memo1: TMemo;
    procedure GoBtnClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure Chromium1AfterCreated(Sender: TObject; const browser: ICefBrowser);
    procedure Chromium1GetResourceResponseFilter(Sender: TObject;
      const browser: ICefBrowser; const frame: ICefFrame;
      const request: ICefRequest; const response: ICefResponse;
      out Result: ICefResponseFilter);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  protected
    FFilter   : ICefResponseFilter;
    FStream   : TMemoryStream;
    FStreamCS : TCriticalSection;
    FLoading  : boolean;

    procedure WMMove(var aMessage : TWMMove); message WM_MOVE;
    procedure WMMoving(var aMessage : TMessage); message WM_MOVING;
    procedure WMEnterMenuLoop(var aMessage: TMessage); message WM_ENTERMENULOOP;
    procedure WMExitMenuLoop(var aMessage: TMessage); message WM_EXITMENULOOP;
    procedure BrowserCreatedMsg(var aMessage : TMessage); message CEF_AFTERCREATED;
    procedure StreamCopyCompleteMsg(var aMessage : TMessage); message STREAM_COPY_COMPLETE;

    procedure Filter_OnFilter(Sender: TObject; data_in: Pointer; data_in_size: NativeUInt; var data_in_read: NativeUInt; data_out: Pointer; data_out_size : NativeUInt; var data_out_written: NativeUInt; var aResult : TCefResponseFilterStatus);
  public
    { Public declarations }
  end;

var
  ResponseFilterBrowserFrm: TResponseFilterBrowserFrm;

implementation

{$R *.dfm}

uses
  {$IFDEF DELPHI16_UP}
  System.Math,
  {$ELSE}
  Math,
  {$ENDIF}
  uCEFApplication;

// This demo uses a TCustomResponseFilter to read the contents from a JavaScript file in wikipedia.org into a TMemoryStream.
// The stream is shown in the TMemo when it's finished.

// For more information read the CEF3 code comments here :
//      https://github.com/chromiumembedded/cef/blob/master/include/capi/cef_response_filter_capi.h

procedure TResponseFilterBrowserFrm.Filter_OnFilter(Sender: TObject;
                                                        data_in          : Pointer;
                                                        data_in_size     : NativeUInt;
                                                    var data_in_read     : NativeUInt;
                                                        data_out         : Pointer;
                                                        data_out_size    : NativeUInt;
                                                    var data_out_written : NativeUInt;
                                                    var aResult          : TCefResponseFilterStatus);
begin
  try
    // This event will be called repeatedly until the input buffer has been fully read.
    FStreamCS.Acquire;

    aResult := RESPONSE_FILTER_DONE;

    if (data_in = nil) then
      begin
        data_in_read     := 0;
        data_out_written := 0;
      end
     else
      begin
        data_in_read := data_in_size;

        if (data_out <> nil) then
          begin
            data_out_written := min(data_in_read, data_out_size);
            Move(data_in^, data_out^, data_out_written);
          end;

        FStream.WriteBuffer(data_in^, data_in_size);
        PostMessage(Handle, STREAM_COPY_COMPLETE, 0, 0);
      end;
  finally
    FStreamCS.Release;
  end;
end;

procedure TResponseFilterBrowserFrm.FormCreate(Sender: TObject);
begin
  FLoading  := False;
  FStream   := TMemoryStream.Create;
  FStreamCS := TCriticalSection.Create;
  FFilter   := TCustomResponseFilter.Create;

  // This event will receive the data
  TCustomResponseFilter(FFilter).OnFilter := Filter_OnFilter;
end;

procedure TResponseFilterBrowserFrm.FormDestroy(Sender: TObject);
begin
  FFilter := nil;
  FStream.Free;
  FStreamCS.Free;
end;

procedure TResponseFilterBrowserFrm.FormShow(Sender: TObject);
begin
  // GlobalCEFApp.GlobalContextInitialized has to be TRUE before creating any browser
  // If it's not initialized yet, we use a simple timer to create the browser later.
  if not(Chromium1.CreateBrowser(CEFWindowParent1)) then Timer1.Enabled := True;
end;

procedure TResponseFilterBrowserFrm.Chromium1AfterCreated(Sender: TObject; const browser: ICefBrowser);
begin
  // Now the browser is fully initialized we can send a message to the main form to load the initial web page.
  PostMessage(Handle, CEF_AFTERCREATED, 0, 0);
end;

procedure TResponseFilterBrowserFrm.Chromium1GetResourceResponseFilter(Sender : TObject;
                                                                       const browser   : ICefBrowser;
                                                                       const frame     : ICefFrame;
                                                                       const request   : ICefRequest;
                                                                       const response  : ICefResponse;
                                                                       out   Result    : ICefResponseFilter);
begin
  // All resources can be filtered but for this demo we will select a JS file in wikipedia.org called 'index-47f5f07682.js'
  if (request <> nil) and
     (pos('index', request.URL) > 0) and  // the file contains the word 'index'
     (pos('.js', request.URL) > 0) then   // the file contains the extension '.js'
    Result := FFilter
   else
    Result := nil;
end;

procedure TResponseFilterBrowserFrm.BrowserCreatedMsg(var aMessage : TMessage);
begin
  Caption            := 'Response Filter Browser';
  AddressPnl.Enabled := True;
  GoBtn.Click;
end;

procedure TResponseFilterBrowserFrm.StreamCopyCompleteMsg(var aMessage : TMessage);
begin
  try
    FStreamCS.Acquire;
    FStream.Seek(0, soBeginning);
    Memo1.Lines.Clear;
    Memo1.Lines.LoadFromStream(FStream);
    FStream.Clear;
  finally
    FStreamCS.Release;
  end;
end;

procedure TResponseFilterBrowserFrm.GoBtnClick(Sender: TObject);
begin
  FLoading := True;
  Chromium1.LoadURL(AddressEdt.Text);
end;

procedure TResponseFilterBrowserFrm.Timer1Timer(Sender: TObject);
begin
  Timer1.Enabled := False;
  if not(Chromium1.CreateBrowser(CEFWindowParent1)) and not(Chromium1.Initialized) then
    Timer1.Enabled := True;
end;

procedure TResponseFilterBrowserFrm.WMMove(var aMessage : TWMMove);
begin
  inherited;

  if (Chromium1 <> nil) then Chromium1.NotifyMoveOrResizeStarted;
end;

procedure TResponseFilterBrowserFrm.WMMoving(var aMessage : TMessage);
begin
  inherited;

  if (Chromium1 <> nil) then Chromium1.NotifyMoveOrResizeStarted;
end;

procedure TResponseFilterBrowserFrm.WMEnterMenuLoop(var aMessage: TMessage);
begin
  inherited;

  if (aMessage.wParam = 0) and (GlobalCEFApp <> nil) then GlobalCEFApp.OsmodalLoop := True;
end;

procedure TResponseFilterBrowserFrm.WMExitMenuLoop(var aMessage: TMessage);
begin
  inherited;

  if (aMessage.wParam = 0) and (GlobalCEFApp <> nil) then GlobalCEFApp.OsmodalLoop := False;
end;

end.
