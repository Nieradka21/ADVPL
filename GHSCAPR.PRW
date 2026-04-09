#INCLUDE "TOTVS.CH"
#INCLUDE "PROTHEUS.CH"
#INCLUDE "PARMTYPE.CH"


Static oQuery := Nil


User Function GHSCAPR()

    FWCallApp('sc-aprovacao')

Return




Static Function JsToAdvpl(oWebChannel, cType, cContent)
    Local jPath := JsonObject():New()
    Local jData := ""

    // Se veio conteúdo do Angular, já transformamos em Objeto AdvPL
    If !Empty(cContent)
        jPath:FromJson(cContent)
    EndIf

    // 1. CARGA INICIAL (Abre a tela limpa)
    If cType == "preLoad"
        // Passa a página 1, termo vazio (""), e array de status vazio ({})
        jData := GetSC1(1, "", {}) 
        oWebChannel:AdvplToJs('preLoad', jData)

        // 2. BUSCA, FILTRO E PAGINAÇÃO (Tudo unificado)
        ElseIf cType == "search_sc"
            
            jData := GetSC1(jPath['pagina'], jPath['termo'], jPath['status'])
            
            // Devolvemos na mesma porta 'preLoad' que o Angular já está escutando
            oWebChannel:AdvplToJs('preLoad', jData)


        ElseIf cType == "get_details"

            jData := GetAll(jPath['filial'], jPath['numero'])

            If !Empty(jData)
                oWebChannel:AdvplToJs('get_details', jData)
            Else
                oWebChannel:AdvplToJs('get_details', '{"success": false, "error": "SC não encontrada"}')
            EndIf 


        ElseIf cType == "approve_sc_batch" .OR. cType == "reject_sc" 

            If AttStatus(jPath['scs'], cType)
                oWebChannel:AdvplToJs( Iif(cType == "approve_sc_batch", 'approve_sc_batch', 'reject_sc'), '{"success": true}')
            Else
                oWebChannel:AdvplToJs( Iif(cType == "approve_sc_batch", 'approve_sc_batch', 'reject_sc'), '{"success": false, "error": "Erro ao atualizar status das SCs"}')
            EndIf

    Endif

Return



Static Function AttStatus(aSCs,cType)

    Local nX
    Local lRet := .F.
    Local aCabec, aItens, aLinha := {}
    Local nOpc := 7

    Private lMsErroAuto := .F.
    Private lMsHelpAuto := .T.

    SC1->(DbSetOrder(1))

    For nX := 1 To Len(aSCs)

        aCabec := {}
        aItens := {}

        If SC1->(MsSeek(aSCs[nX]['filial'] + aSCs[nX]['numero']))

            // CABEÇALHO
            aAdd(aCabec, {"C1_FILIAL",SC1->C1_FILIAL})
            aAdd(aCabec, {"C1_NUM",SC1->C1_NUM})
            aAdd(aCabec, {"C1_EMISSAO", SC1->C1_EMISSAO})
            aAdd(aCabec, {"C1_SOLICIT",SC1->C1_SOLICIT})

            If cType == "approve_sc_batch"
                aAdd(aCabec, {"C1_APROV","L"})
            ElseIf cType == "reject_sc"
                aAdd(aCabec, {"C1_APROV","R"})
            Else
                aAdd(aCabec, {"C1_APROV","B"})
            EndIf

            // ITENS
            While !SC1->(Eof()) .And. ;
                  SC1->C1_FILIAL == aSCs[nX]['filial'] .And. ;
                  SC1->C1_NUM == aSCs[nX]['numero']

                aLinha := {}

                aAdd(aLinha,{"C1_FILIAL",SC1->C1_FILIAL})
                aAdd(aLinha,{"C1_ITEM",SC1->C1_ITEM,Nil})
                aAdd(aLinha,{"C1_PRODUTO",SC1->C1_PRODUTO,Nil})
                aAdd(aLinha,{"C1_QUANT",SC1->C1_QUANT,Nil})

                aAdd(aItens,aLinha)

                SC1->(DbSkip())

            EndDo

            MsExecAuto({|u,v,x,y,z| MATA110(u,v,x)},aCabec,aItens,nOpc)

            If !lMsErroAuto
                lRet := .T.
            Else
                MostraErro()
            EndIf

        EndIf

    Next nX

Return lRet


Static Function GetSC1(nPagina, cTermo, aStatus)
    Local cQuery := ""
    Local nParam := 1
    Local cAlias := ""
    Local jData  := JsonObject():New()
    Local jItem 
    Local aData  := {}
    Local nPageSize := 10
    // Calcula a partir de qual registro começar (Ex: Pag 1 = 0, Pag 2 = 10)
    Local nOffset   := (nPagina - 1) * nPageSize 

    Default nPagina := 1

    cQuery := "SELECT C1_FILIAL, C1_NUM, C1_SOLICIT, "
    cQuery += "CASE WHEN C1_XCODAPR IS NULL OR C1_XCODAPR = '' THEN AI_XAPROVD ELSE C1_XCODAPR END APROVADOR, "
    cQuery += "C1_APROV FROM ? SC1 " // 1 = SC1
    cQuery += "LEFT JOIN ? SAI ON SAI.AI_USER = SC1.C1_XSOL "  // 2 = SAI
    cQuery += "AND SAI.D_E_L_E_T_ = ? "  // 3 = ' '
    cQuery += "WHERE SC1.D_E_L_E_T_ = ? "  // 4 = ' '
    If !Empty(cTermo)
        cQuery += " AND SC1.C1_NUM = ? " // 5 = cTermo
    EndIf
    If Len(aStatus) > 0
        cQuery += " AND SC1.C1_APROV IN (?) " // 6 = aStatus
    EndIf
    cQuery += "AND CASE WHEN C1_XCODAPR IS NULL OR C1_XCODAPR = '' THEN AI_XAPROVD ELSE C1_XCODAPR END = ? "  // 7 USER'
    cQuery += "GROUP BY C1_FILIAL, "
    cQuery += "C1_NUM, "
    cQuery += "C1_SOLICIT, "
    cQuery += "C1_XCODAPR, "
    cQuery += "AI_XAPROVD, "
    cQuery += "C1_XCODAPR, "
    cQuery += "C1_APROV "
    cQuery += "ORDER BY C1_NUM DESC "
    cQuery += "OFFSET ? ROWS FETCH NEXT ? ROWS ONLY " // 8 = nOffset, 9 = nPageSize
    oQuery := FwExecStatement():New(cQuery)


    oQuery:SetUnSafe(nParam++, RetSqlName("SC1"))
    oQuery:SetUnSafe(nParam++, RetSqlName("SAI"))
    oQuery:SetString(nParam++, ' ')
    oQuery:SetString(nParam++, ' ')
    If !Empty(cTermo)
        oQuery:SetString(nParam++, Alltrim(cTermo))
    EndIf
    If Len(aStatus) > 0
        oQuery:SetIn(nParam++, aStatus)
    EndIf
    oQuery:SetString(nParam++, AllTrim(__cUserId))
    
    // Aqui entra a mágica da paginação
    oQuery:SetUnSafe(nParam++, cValToChar(nOffset))   // Pula os anteriores
    oQuery:SetUnSafe(nParam++, cValToChar(nPageSize)) // Busca os próximos 10

    cAlias := oQuery:OpenAlias()

    While !(cAlias)->(Eof())
        jItem := JsonObject():New()
        jItem['filial']      := AllTrim((cAlias)->C1_FILIAL)
        jItem['numero']      := AllTrim((cAlias)->C1_NUM)
        jItem['solicitante'] := AllTrim((cAlias)->C1_SOLICIT)
        jItem['aprovador']   := AllTrim((cAlias)->APROVADOR)
        jItem['status']      := AllTrim((cAlias)->C1_APROV)
        aAdd(aData, jItem)
        (cAlias)->(DbSkip())
    EndDo

    jData['pagina']  := nPagina
    // Se trouxe 10 itens, avisamos o Angular que PROVAVELMENTE tem mais
    jData['hasNext'] := ( Len(aData) == nPageSize )
    jData['itens']   := aData

    (cAlias)->(DbCloseArea())

Return jData:ToJson()


Static Function GetAll(cFil, cNumero)

    Local cQuery        := ""
    Local nParam        := 1
    Local cAlias        := ""
    Local jData         := JsonObject():New()
    Local jCabecalho    := JsonObject():New()
    Local jItem
    Local aItens        := {}
    Local lCabecalhoSet := .F.
    Local oQueryAll

    cQuery := "SELECT "
    cQuery += "C1_NUM, "
    cQuery += "C1_FILIAL, "
    cQuery += "C1_SOLICIT, "
    cQuery += "C1_EMISSAO, "
    cQuery += "C1_ITEM, "
    cQuery += "C1_PRODUTO, "
    cQuery += "C1_DESCRI, "
    cQuery += "C1_QUANT, "
    cQuery += "C1_PRECO, "
    cQuery += "C1_TOTAL "
    cQuery += "FROM ? SC1 "
    cQuery += "WHERE SC1.C1_FILIAL = ? "
    cQuery += "AND SC1.C1_NUM = ? "
    cQuery += "AND SC1.D_E_L_E_T_ = ? "
    cQuery += "ORDER BY SC1.C1_ITEM "

    oQueryAll := FwExecStatement():New(cQuery)

    oQueryAll:SetUnSafe(nParam++, RetSqlName("SC1"))
    oQueryAll:SetString(nParam++, AllTrim(cFil))
    oQueryAll:SetString(nParam++, AllTrim(cNumero))
    oQueryAll:SetString(nParam++, ' ')

    cAlias := oQueryAll:OpenAlias()

    While !(cAlias)->(Eof())

        // Cabeçalho (apenas 1 vez)
        If !lCabecalhoSet

            jCabecalho := JsonObject():New()

            jCabecalho['filial']      := AllTrim((cAlias)->C1_FILIAL)
            jCabecalho['numero']      := AllTrim((cAlias)->C1_NUM)
            jCabecalho['solicitante'] := AllTrim((cAlias)->C1_SOLICIT)
            jCabecalho['emissao']     := StoD((cAlias)->C1_EMISSAO)

            lCabecalhoSet := .T.

        EndIf

        // Itens
        jItem := JsonObject():New()
        jItem['item']       := (cAlias)->C1_ITEM
        jItem['produto']    := AllTrim((cAlias)->C1_PRODUTO)
        jItem['descricao']  := AllTrim((cAlias)->C1_DESCRI)
        jItem['quantidade'] := (cAlias)->C1_QUANT
        jItem['preco']      := (cAlias)->C1_PRECO
        jItem['total']      := (cAlias)->C1_TOTAL

        aAdd(aItens, jItem)

        (cAlias)->(DbSkip())

    EndDo

    // Monta JSON final
    jData['cabecalho'] := jCabecalho
    jData['itens']     := aItens

    (cAlias)->(DbCloseArea())

Return jData:ToJson()
