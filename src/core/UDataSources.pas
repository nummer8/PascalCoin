unit UDataSources;

{$mode delphi}
{$modeswitch nestedprocvars}

interface

uses
  Classes, SysUtils, UAccounts, UNode, UBlockchain, UCommon, UMemory, UConst, UCommon.Data, UCommon.Collections, Generics.Collections, Generics.Defaults, syncobjs;

type

  { TAccountsDataSourceBase }

  TAccountsDataSourceBase = class(TCustomDataSource<TAccount>)
    protected
      function GetItemDisposePolicy : TDisposePolicy; override;
      function GetColumns : TDataColumns;  override;
    public
      function GetEntityKey(constref AItem: TAccount) : Variant; override;
      function GetItemField(constref AItem: TAccount; const ABindingName : AnsiString) : Variant; override;
      procedure DehydrateItem(constref AItem: TAccount; var ATableRow: Variant); override;
  end;

  { TAccountsDataSource }

  TAccountsDataSource = class(TAccountsDataSourceBase)
    public type
      TOverview = record
        TotalPASC : UInt64;
        TotalPASA : Cardinal;
      end;
    private
      FLastKnownUserAccounts : TArray<TAccount>;
      FKeys : TSortedHashSet<TAccountKey>;
    protected
      FLastOverview : TOverview;
      function GetFilterKeys : TArray<TAccountKey>;
      procedure SetFilterKeys (const AKeys : TArray<TAccountKey>);
    public
      property Overview : TOverview read FLastOverview;
      property LastFetchResult : TArray<TAccount> read FLastKnownUserAccounts;
      property FilterKeys : TArray<TAccountKey> read GetFilterKeys write SetFilterKeys;
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      procedure FetchAll(const AContainer : TList<TAccount>); override;
  end;

  { TOperationsDataSourceBase }

  TOperationsDataSourceBase = class(TCustomDataSource<TOperationResume>)
    private
      FStart, FEnd : Cardinal;
      function GetTimeSpan : TTimeSpan;
      procedure SetTimeSpan(const ASpan : TTimeSpan);
    protected
      function GetItemDisposePolicy : TDisposePolicy; override;
      function GetColumns : TDataColumns;  override;
    public
      constructor Create(AOwner: TComponent); override;
      property TimeSpan : TTimeSpan read GetTimeSpan write SetTimeSpan;
      property StartBlock : Cardinal read FStart write FStart;
      property EndBlock : Cardinal read FEnd write FEnd;
      function GetEntityKey(constref AItem: TOperationResume) : Variant; override;
      function GetItemField(constref AItem: TOperationResume; const ABindingName : AnsiString) : Variant; override;
      procedure DehydrateItem(constref AItem: TOperationResume; var ATableRow: Variant); override;
  end;

  { TAccountsOperationsDataSource }

  TAccountsOperationsDataSource = class(TOperationsDataSourceBase)
    private
      FAccounts : TSortedHashSet<Cardinal>;
      function GetAccounts : TArray<Cardinal> ;
      procedure SetAccounts(const AAccounts : TArray<Cardinal>);
    public
      constructor Create(AOwner: TComponent);
      destructor Destroy;
      property Accounts : TArray<Cardinal> read GetAccounts write SetAccounts;
      procedure FetchAll(const AContainer : TList<TOperationResume>); override;
  end;

  { TPendingOperationsDataSource }

  TPendingOperationsDataSource = class(TOperationsDataSourceBase)
    public
      procedure FetchAll(const AContainer : TList<TOperationResume>); override;
  end;

  { TOperationsDataSource }

  TOperationsDataSource = class(TOperationsDataSourceBase)
    public
      procedure FetchAll(const AContainer : TList<TOperationResume>); override;
  end;

  { TDataSourceTool }

  TDataSourceTool = class
    class function OperationShortHash(const AOpHash : AnsiString) : AnsiString;
    class function OperationShortText(const OpType, OpSubType : DWord) : AnsiString;
    class function AccountKeyShortText(const AText : AnsiString) : AnsiString;
  end;

implementation

uses
  math, UCore, UWallet, UUserInterface, UTime;

{ TAccountsDataSourceBase }

function TAccountsDataSourceBase.GetItemDisposePolicy : TDisposePolicy;
begin
  Result := idpNone;
end;

function TAccountsDataSourceBase.GetColumns : TDataColumns;
begin
  Result := TDataColumns.Create(
    TDataColumn.From('Account'),
    TDataColumn.From('Name'),
    TDataColumn.From('Balance'),
    TDataColumn.From('Key'),
    TDataColumn.From('State'),
    TDataColumn.From('Price'),
    TDataColumn.From('LockedUntil')
  );
end;

function TAccountsDataSourceBase.GetEntityKey(constref AItem: TAccount) : Variant;
begin
  Result := AItem.account;
end;

function TAccountsDataSourceBase.GetItemField(constref AItem: TAccount; const ABindingName : AnsiString) : Variant;
var
  index : Integer;
begin
   if ABindingName = 'Account' then
     Result := AItem.account
   else if ABindingName = 'Name' then
     Result := AItem.name
   else if ABindingName = 'Balance' then
     Result := TAccountComp.FormatMoneyDecimal(AItem.Balance)
{   else if ABindingName = 'Key' then begin
     index := TWallet.Keys.AccountsKeyList.IndexOfAccountKey(AItem.accountInfo.accountKey);
     if index>=0 then
        Result := TWallet.Keys[index].Name
     else
         Result := TAccountComp.AccountPublicKeyExport(AItem.accountInfo.accountKey); }
   else if ABindingName = 'Key' then
     Result := TAccountComp.AccountPublicKeyExport(AItem.accountInfo.accountKey)
   else if ABindingName = 'AccType' then
     Result := AItem.account_type
   else if ABindingName = 'State' then
     Result := AItem.accountInfo.state
   else if ABindingName = 'Price' then
     Result := TAccountComp.FormatMoneyDecimal(AItem.accountInfo.price)
   else if ABindingName = 'LockedUntil' then
     Result := AItem.accountInfo.locked_until_block
   else raise Exception.Create(Format('Field not found "%s"', [ABindingName]));
end;

procedure TAccountsDataSourceBase.DehydrateItem(constref AItem: TAccount; var ATableRow: Variant);
//var
//  index : Integer;
begin
  // 'Account', 'Name', 'Balance', 'Key', 'AccType', 'State', 'Price', 'LockedUntil'
  ATableRow.Account := TAccountComp.AccountNumberToAccountTxtNumber(AItem.account);
  ATableRow.Name := Variant(AItem.name);
  ATableRow.Balance := TAccountComp.FormatMoney(AItem.balance);
  ATableRow.Key := TAccountComp.AccountPublicKeyExport(AItem.accountInfo.accountKey);
  ATableRow.AccType := Word(AItem.account_type);
  ATableRow.State := Cardinal(AItem.accountInfo.state);
  ATableRow.Price := TAccountComp.FormatMoney(Aitem.accountInfo.price);
  ATableRow.LockedUntil := LongWord(AItem.accountInfo.locked_until_block);
end;

{ TAccountsDataSource }

constructor TAccountsDataSource.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKeys := TSortedHashSet<TAccountKey>.Create(TAccountKeyComparer.Create, TAccountKeyEqualityComparer.Create);
end;

destructor TAccountsDataSource.Destroy;
begin
  FKeys.Free;
end;

function TAccountsDataSource.GetFilterKeys : TArray<TAccountKey>;
begin
  Result := FKeys.ToArray;
end;

procedure TAccountsDataSource.SetFilterKeys (const AKeys : TArray<TAccountKey>);
var i : Integer;
begin
  FKeys.Clear;
  for i := Low(AKeys) to High(AKeys) do
    FKeys.Add(AKeys[i]);
end;

procedure TAccountsDataSource.FetchAll(const AContainer : TList<TAccount>);
var
  i,j : integer;
  acc : TAccount;
  safeBox : TPCSafeBox;
  GC : TDisposables;
  left,right:TAccountKey;
begin
  FLastOverview.TotalPASC := 0;
  FLastOverview.TotalPASA := 0;
  safeBox := TUserInterface.Node.Bank.SafeBox;
  safeBox.StartThreadSafe;
  try
   if FKeys.Count = 0 then
     for i := 0 to safeBox.AccountsCount - 1 do begin
       // Load all accounts
       AContainer.Add(safeBox.Account(i));
       FLastOverview.TotalPASC := FLastOverview.TotalPASC + acc.Balance;
       inc(FLastOverview.TotalPASA);
     end
   else begin
     // load key-matching accounts
     for i := 0 to safeBox.AccountsCount - 1 do begin
       acc := safeBox.Account(i);
       if FKeys.Contains(acc.accountInfo.accountKey) then begin
         AContainer.Add(acc);
         FLastOverview.TotalPASC := FLastOverview.TotalPASC + acc.Balance;
         inc(FLastOverview.TotalPASA);
       end else begin
         for left in FKeys do begin
           right := acc.accountInfo.accountKey;

         end;
       end;
     end;
   end;
  finally
   safeBox.EndThreadSave;
  end;
  FLastKnownUserAccounts := AContainer.ToArray;
end;

{ TOperationsDataSourceBase }

constructor TOperationsDataSourceBase.Create(AOwner:TComponent);
var
  node : TNode;
begin
 inherited Create(AOwner);
 node := TNode.Node;
  if Assigned(Node) then begin
    FStart := 0;
    FEnd := node.Bank.BlocksCount - 1;
  end else begin
    FStart := 0;
    FEnd := 0;
  end;
end;

function TOperationsDataSourceBase.GetTimeSpan : TTimeSpan;
begin
  Result := TTimeSpan.FromSeconds( CT_NewLineSecondsAvg * (FEnd - FStart + 1) );
  //XXXXXXXXXX TTimeSpan use not available at TPCOperationsComp  Result := TPCOperationsComp.ConvertBlockCountToTimeSpan(FEnd - FStart + 1);
end;

procedure TOperationsDataSourceBase.SetTimeSpan(const ASpan : TTimeSpan);
var
  node : TNode;
begin
 node := TNode.Node;
 if Not Assigned(Node) then exit;
 FEnd := node.Bank.BlocksCount - 1;
 FStart := ClipValue(FEnd - (Round( ASpan.TotalSeconds / CT_NewLineSecondsAvg ) + 1), 0, FEnd);
 //XXXXXXXXXX TTimeSpan use not available at TPCOperationsComp  FStart := ClipValue(FEnd - (TPCOperationsComp.ConvertTimeSpanToBlockCount(ASpan) + 1), 0, FEnd);
end;

function TOperationsDataSourceBase.GetItemDisposePolicy : TDisposePolicy;
begin
  Result := idpNone;
end;

function TOperationsDataSourceBase.GetColumns : TDataColumns;
begin
  Result := TDataColumns.Create(
    TDataColumn.From('Time'),
    TDataColumn.From('Block'),
    TDataColumn.From('Account'),
    TDataColumn.From('Type'),
    TDataColumn.From('Amount'),
    TDataColumn.From('Fee'),
    TDataColumn.From('Balance'),
    TDataColumn.From('Payload'),
    TDataColumn.From('OPHASH'),
    TDataColumn.From('Description')
  );
end;

function TOperationsDataSourceBase.GetEntityKey(constref AItem: TOperationResume) : Variant;
begin
  if AItem.valid then
    Result := TPCOperation.OperationHashAsHexa(AItem.OperationHash)
  else
    Result := nil;
end;

function TOperationsDataSourceBase.GetItemField(constref AItem: TOperationResume; const ABindingName : AnsiString) : Variant;
var
  index : Integer;
begin
   if ABindingName = 'Time' then
     Result := AItem.Time
   else if ABindingName = 'Block' then
     Result := UInt64(AItem.Block) * 4294967296 + UInt32(AItem.NOpInsideBlock)   // number pattern = [block][opindex]
   else if ABindingName = 'Account' then
     Result := AItem.AffectedAccount
   else if ABindingName = 'Type' then
     Result := AItem.OpSubtype
   else if ABindingName = 'Amount' then
     Result := TAccountComp.FormatMoneyDecimal(AItem.Amount)
   else if ABindingName = 'Fee' then
     Result := TAccountComp.FormatMoneyDecimal(AItem.Fee)
   else if ABindingName = 'Balance' then
     Result := TAccountComp.FormatMoneyDecimal(AItem.Balance)
   else if ABindingName = 'Payload' then
     Result := AItem.PrintablePayload
   else if ABindingName = 'OPHASH' then
     Result := TPCOperation.OperationHashAsHexa(AItem.OperationHash)
   else if ABindingName = 'Description' then
     Result :=  AItem.OperationTxt
   else raise Exception.Create(Format('Field not found [%s]', [ABindingName]));
end;

procedure TOperationsDataSourceBase.DehydrateItem(constref AItem: TOperationResume; var ATableRow: Variant);
var
  index : Integer;
  s: ansistring;
begin
  // Time
  ATableRow.Time := UnixTimeToLocalStr(AItem.time);

  // Block
  if AItem.OpType <> CT_PseudoOp_Reward then
    ATableRow.Block := Inttostr(AItem.Block) + '/' + Inttostr(AItem.NOpInsideBlock+1)
  else
    ATableRow.Block := Inttostr(AItem.Block);

  // Account
  ATableRow.Account := TAccountComp.AccountNumberToAccountTxtNumber(AItem.AffectedAccount);

  // Type
  ATableRow.&Type := Variant(TDataSourceTool.OperationShortText(AItem.OpType, AItem.OpSubtype));

  // Amount
  ATableRow.Amount := AItem.Amount;

  // Fee
  ATableRow.Fee := TAccountComp.FormatMoney(AItem.Fee);
  {  if opr.Fee>0 then DrawGrid.Canvas.Font.Color := ClGreen
  else if opr.Fee=0 then DrawGrid.Canvas.Font.Color := clGrayText
  else DrawGrid.Canvas.Font.Color := clRed;}

  // Balance
  if AItem.time=0 then
     ATableRow.Balance := '('+TAccountComp.FormatMoney(AItem.Balance)+')'
  else
     ATableRow.Balance := TAccountComp.FormatMoney(AItem.Balance);
  {  if opr.time=0 then begin
    // Pending operation... showing final balance
    DrawGrid.Canvas.Font.Color := clBlue;
    s := '('+TAccountComp.FormatMoney(opr.Balance)+')';
  end else begin
    s := TAccountComp.FormatMoney(opr.Balance);
    if opr.Balance>0 then DrawGrid.Canvas.Font.Color := ClGreen
    else if opr.Balance=0 then DrawGrid.Canvas.Font.Color := clGrayText
    else DrawGrid.Canvas.Font.Color := clRed;
  end;
  Canvas_TextRect(DrawGrid.Canvas,Rect,s,State,[tfRight,tfVerticalCenter,tfSingleLine]);
  }

  // Payload
  ATableRow.Payload := IIF(NOT AnsiString.IsNullOrWhiteSpace(AItem.PrintablePayload), True, False);
  {    s := opr.PrintablePayload;
  Canvas_TextRect(DrawGrid.Canvas,Rect,s,State,[tfLeft,tfVerticalCenter,tfSingleLine]); }

  // OPHASH
  if Length(AItem.OperationHash) > 0 then
    ATableRow.OPHASH := TDataSourceTool.OperationShortHash( TPCOperation.OperationHashAsHexa(AItem.OperationHash) )
  else
    ATableRow.OPHASH := 'None';

  // Description
  ATableRow.Description := Variant(AItem.OperationTxt);

end;

{ TAccountsOperationsDataSource }

constructor TAccountsOperationsDataSource.Create(AOwner:TComponent);
begin
  inherited Create(AOwner);
  FAccounts := TSortedHashSet<Cardinal>.Create;
end;

destructor TAccountsOperationsDataSource.Destroy;
begin
 Inherited;
 FAccounts.Free;
end;

function TAccountsOperationsDataSource.GetAccounts : TArray<Cardinal> ;
begin
  Result := FAccounts.ToArray;
end;

procedure TAccountsOperationsDataSource.SetAccounts(const AAccounts : TArray<Cardinal>);
begin
  FAccounts.Clear;
  FAccounts.AddRange(AAccounts);
end;

procedure TAccountsOperationsDataSource.FetchAll(const AContainer : TList<TOperationResume>);
var
  block, i, keyIndex : integer;
  OPR : TOperationResume;
  accountBlockOps : TOperationsResumeList;
  node : TNode;
  list : Classes.TList;
  Op : TPCOperation;
  acc : Cardinal;
  GC : TDisposables;
begin
  if FAccounts.Count = 0
    then exit;
  node := TNode.Node;
  if Not Assigned(Node)
    then exit;
  TUserInterface.Node.Bank.SafeBox.StartThreadSafe;
  try
    accountBlockOps := GC.AddObject(TOperationsResumeList.Create ) as TOperationsResumeList;
    list := GC.AddObject( Classes.TList.Create ) as Classes.TList;
    for acc in FAccounts do begin
      // Load pending operations first
      list.Clear;
      accountBlockOps.Clear;
      Node.Operations.OperationsHashTree.GetOperationsAffectingAccount( acc, list );
      if list.Count > 0 then
        for i := list.Count - 1 downto 0 do begin
          Op := node.Operations.OperationsHashTree.GetOperation( PtrInt( list[i] ) );
          If TPCOperation.OperationToOperationResume( 0, Op, acc, OPR ) then begin
            OPR.NOpInsideBlock := i;
            OPR.Block := Node.Operations.OperationBlock.block; ;
            OPR.Balance := Node.Operations.SafeBoxTransaction.Account( acc {Op.SignerAccount} ).balance;
            AContainer.Add(OPR);
          end;
      end;

      // Load block ops
      Node.GetStoredOperationsFromAccount(accountBlockOps, acc, MaxInt, 0, MaxInt);
      for i := 0 to accountBlockOps.Count - 1 do
        AContainer.Add(accountBlockOps[i]);
    end;
  finally
   TUserInterface.Node.Bank.SafeBox.EndThreadSave;
  end;
end;

{ TPendingOperationsDataSource }

procedure TPendingOperationsDataSource.FetchAll(const AContainer : TList<TOperationResume>);
var
  i : integer;
  node : TNode;
  Op : TPCOperation;
  OPR : TOperationResume;
begin
 node := TNode.Node;
  if Not Assigned(Node) then exit;
  for i := Node.Operations.Count - 1 downto 0 do begin
    Op := Node.Operations.OperationsHashTree.GetOperation(i);
    If TPCOperation.OperationToOperationResume(0,Op,Op.SignerAccount,OPR) then begin
      OPR.NOpInsideBlock := i;
      OPR.Block := Node.Bank.BlocksCount;
      OPR.Balance := Node.Operations.SafeBoxTransaction.Account(Op.SignerAccount).balance;
      AContainer.Add(OPR);
    end;
  end;
end;


{ TOperationsDataSource }

procedure TOperationsDataSource.FetchAll(const AContainer : TList<TOperationResume>);
var
  block, i, j, keyIndex : integer;
  OPR : TOperationResume;
  blockOps : TPCOperationsComp;
  node : TNode;
  GC : TDisposables;

begin
  node := TNode.Node;
  if Not Assigned(Node) then exit;
  blockOps := GC.AddObject(TPCOperationsComp.Create(Nil)) as TPCOperationsComp;
  for block := FEnd downto FStart do begin  /// iterate blocks correctly
    opr := CT_TOperationResume_NUL;
    if (Node.Bank.Storage.LoadBlockChainBlock(blockOps, block)) then begin
      AContainer.Add( blockOps.GetMinerRewardPseudoOperation );
      if blockOps.Count = 0 then exit;
      for i := blockOps.Count - 1 downto 0 do begin    // reverse order
        if TPCOperation.OperationToOperationResume(block, blockOps.Operation[i], blockOps.Operation[i].SignerAccount, opr) then begin
          opr.NOpInsideBlock := i;
          opr.Block := block;
          opr.time := blockOps.OperationBlock.timestamp;
          AContainer.Add(opr);
        end;
      end;
    end else break;
  end;
end;

{ TDataSourceTool }

class function TDataSourceTool.OperationShortHash(const AOpHash : AnsiString) : AnsiString;
var
  len : SizeInt;
begin
 len := Length(AOpHash);
  if len > 8 then
    result := AOpHash.Substring(0, 4) + '...' + AOpHash.Substring(len - 4 - 1, 4)
  else
    result := AOpHash;
end;

class function TDataSourceTool.OperationShortText(const OpType, OpSubType : DWord) : AnsiString;
begin
  case OpType of
    CT_PseudoOp_Reward: case OpSubType of
      0, CT_PseudoOpSubtype_Miner : result := 'Miner Reward';
      CT_PseudoOpSubtype_Developer : result := 'Developer Reward';
      else result := 'Unknown';
    end;
    CT_Op_Transaction: case OpSubType of
      CT_OpSubtype_TransactionSender: Result := 'Send';
      CT_OpSubtype_TransactionReceiver: Result := 'Receive';
      CT_OpSubtype_BuyTransactionBuyer: result := 'Buy Account Direct';
      CT_OpSubtype_BuyTransactionTarget: result := 'Purchased Account Direct';
      CT_OpSubtype_BuyTransactionSeller: result := 'Sold Account Direct';
      else result := 'Unknown';
    end;
    CT_Op_Changekey: Result := 'Change Key (legacy)';
    CT_Op_Recover: Result := 'Recover';
    CT_Op_ListAccountForSale: case OpSubType of
      CT_OpSubtype_ListAccountForPublicSale: result := 'For Sale';
      CT_OpSubtype_ListAccountForPrivateSale: result := 'Exclusive Sale';
      else result := 'Unknown';
    end;
    CT_Op_DelistAccount: result := 'Remove Sale';
    CT_Op_BuyAccount: case OpSubType of
      CT_OpSubtype_BuyAccountBuyer: result := 'Buy Account';
      CT_OpSubtype_BuyAccountTarget: result := 'Purchased Account';
      CT_OpSubtype_BuyAccountSeller: result := 'Sold Account';
      else result := 'Unknown';
    end;
    CT_Op_ChangeKeySigned: result :=  'Change Key';
    CT_Op_ChangeAccountInfo: result := 'Change Info';
    else result := 'Unknown';
  end;
end;

class function TDataSourceTool.AccountKeyShortText(const AText : AnsiString) : AnsiString;
begin
 If Length(AText) > 20 then
   Result := AText.SubString(0, 17) + '...'
 else
   Result := AText;
end;

end.
