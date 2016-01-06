VERSION 5.00
Begin VB.Form FormRedEye 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Red eye removal"
   ClientHeight    =   6540
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   12030
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   436
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   802
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.sliderTextCombo sltIntensity 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   2280
      Width           =   5880
      _ExtentX        =   10372
      _ExtentY        =   1270
      Caption         =   "intensity"
      Min             =   1
      SigDigits       =   2
      Value           =   2
   End
   Begin PhotoDemon.fxPreviewCtl fxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
   End
   Begin PhotoDemon.commandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5790
      Width           =   12030
      _ExtentX        =   21220
      _ExtentY        =   1323
      BackColor       =   14802140
   End
End
Attribute VB_Name = "FormRedEye"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Automated Red Eye Correction Tool
'Copyright 2015-2016 by Tanner Helland
'Created: 29/December/15
'Last updated: 29/December/15
'Last update: initial build
'
'Comments TODO
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Apply automated red-eye correction
Public Sub ApplyRedEyeCorrection(ByVal parameterList As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As fxPreviewCtl)
    
    'Parse out the parameter list
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.setParamString parameterList
    
    If Not toPreview Then Message "Searching image for red-eye artifacts..."
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim ImageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    
    prepImageData tmpSA, toPreview, dstPic
    CopyMemory ByVal VarPtrArray(ImageData()), VarPtr(tmpSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim quickX As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    If Not toPreview Then
        SetProgBarMax finalY
        progBarCheck = findBestProgBarValue()
    End If
    
    'Color and grayscale variables
    Dim r As Long, g As Long, b As Long
    Dim rRatio As Double, gRatio As Double, bRatio As Double, pxSum As Double
    
    'We need an array the size of the image to track various pixel statistics.  Each pixel will be sorted into a variety
    ' of potential categories, and because we're applying region analysis to the image, we need to gather statistical data
    ' on large numbers of pixels at a time.
    Dim redEyeData() As Byte
    ReDim redEyeData(initX To finalX, initY To finalY) As Byte
    
    'For large segments of our heuristics, we're only going to be referring to the red channel in the image.
    ' By stripping out red and green bytes, we can reduce memory access times and cache competition.
    Dim redMap() As Byte
    ReDim redMap(initX To finalX, initY To finalY) As Byte
    
    'A few constants to make this code easier to read.  We use a lot of "magic numbers" during red-eye analysis, alas.
    Const PIXEL_IS_NON_SKIN As Long = 1
    Const PIXEL_IS_MOSTLY_RED As Long = 2
    Const PIXEL_IS_INTERIOR_HIGHLIGHT As Long = 3
    
    'Start with a basic red-eye analysis heuristic.  In this step, we simply want to mark "red" pixels.  This initial
    ' data set will then be sorted into "red regions", and because we pre-check redness, we can perform our region
    ' analysis much more quickly.
    For y = initY To finalY
    For x = initX To finalX
        quickX = x * qvDepth
    
        'Get the source pixel color values
        b = ImageData(quickX, y)
        g = ImageData(quickX + 1, y)
        r = ImageData(quickX + 2, y)
        
        'Strip red bytes into a separate tracking array
        redMap(x, y) = r    '(r + g + b) \ 3
        
        'Calculate relative RGB sums
        pxSum = r + g + b
        If pxSum <> 0 Then
        
            rRatio = r / pxSum
            gRatio = g / pxSum
            bRatio = b / pxSum
        
            'Use Microsoft's suggested threshold for "redness"; http://research.microsoft.com/en-us/um/people/leizhang/paper/icip04-lei.pdf
            If r > 50 Then
                If rRatio > 0.4 Then
                    If gRatio < 0.31 Then
                        If bRatio < 0.36 Then
                            redEyeData(x, y) = PIXEL_IS_MOSTLY_RED
                        End If
                    End If
                End If
            End If
            
            If redEyeData(x, y) = PIXEL_IS_MOSTLY_RED Then
                
                'DEBUG ONLY!  Paint red pixels red, so we can visualize the output of our heuristics
                ImageData(quickX, y) = 0
                ImageData(quickX + 1, y) = 0
                ImageData(quickX + 2, y) = 255
                
            'If this is a non-red pixel, see if we can mark it as non-skin.  This allows us to completely bypass the
            ' pixel on subsequent heuristic passes.
            Else
                If gRatio > 0.4 Then redEyeData(x, y) = PIXEL_IS_NON_SKIN
                If bRatio > 0.45 Then redEyeData(x, y) = PIXEL_IS_NON_SKIN
                
                'DEBUG ONLY!  Paint non-skin pixels blue, so we can visualize the output of our heuristics
                If redEyeData(x, y) = PIXEL_IS_NON_SKIN Then
                    ImageData(quickX, y) = 255
                    ImageData(quickX + 1, y) = 0
                    ImageData(quickX + 2, y) = 0
                End If
            End If
            
        End If
        
    Next x
        If Not toPreview Then
            If (y And progBarCheck) = 0 Then
                If userPressedESC() Then Exit For
                SetProgBarVal y
            End If
        End If
    Next y
    
    'With a redness map generated, we are now going to apply a second pass to the image, using our redness data as
    ' one of our inputs.  The goal of this step is to mark "highlight" pixels.
    
    'Because we are performing neighborhood searches, and red eyes are unlikely to appear exactly on image borders,
    ' we can shrink our processing area to save some time and resources.
    Dim hlInitX As Long, hlInitY As Long, hlFinalX As Long, hlFinalY As Long
    hlInitX = initX + 2
    hlInitY = initY + 2
    hlFinalX = finalX - 3
    hlFinalY = finalY - 3
    
    Dim hTotal As Long, sTotal As Long, rTotal As Long
    Dim i As Long, j As Long
    
    For y = hlInitY To hlFinalY
    For x = hlInitX To hlFinalX
        
        'Apply a basic shadow mask to this pixel; the goal here is to attempt to flag "highlight" pixels in the
        ' center of a red-eye region.  By checking for highlight regions surrounded by red regions, we can greatly
        ' reduce the occurence of false-positives.
        
        'Code blocks here are grouped by row; six rows in total are processed for each pixel.
        sTotal = redMap(x - 1, y - 2)
        sTotal = sTotal + redMap(x, y - 2)
        sTotal = sTotal + redMap(x + 1, y - 2)
        sTotal = sTotal + redMap(x + 2, y - 2)
            
        sTotal = sTotal + redMap(x - 1, y - 1)
        sTotal = sTotal + redMap(x + 2, y - 1)
            
        sTotal = sTotal + redMap(x - 1, y)
        hTotal = redMap(x, y)
        hTotal = hTotal + redMap(x + 1, y)
        sTotal = sTotal + redMap(x + 2, y)
            
        sTotal = sTotal + redMap(x - 1, y + 1)
        hTotal = hTotal + redMap(x, y + 1)
        hTotal = hTotal + redMap(x + 1, y + 1)
        sTotal = sTotal + redMap(x + 2, y + 1)
            
        sTotal = sTotal + redMap(x - 1, y + 2)
        sTotal = sTotal + redMap(x, y + 2)
        sTotal = sTotal + redMap(x + 1, y + 2)
        sTotal = sTotal + redMap(x + 2, y + 2)
        
        'If the highlight vs shadow ratio is acceptable, continue processing this pixel.  Note that the original MS paper
        ' strangely says "> 140" which is an astronomical difference, and one that never results in actual regions
        ' being found.  14 seems to be a good compromise between accuracy and false-positive potential, so I'm assuming
        ' their original 140 value was just a typo.
        If ((hTotal \ 4) - (sTotal \ 16)) > 14 Then
            
            'Count the number of "red" pixels in this sub-region.  To be a true "highlight" pixel, there must be
            ' at least ten red pixels in the subregion
            rTotal = 0
            
            For j = y - 2 To y + 3
            For i = x - 2 To x + 3
                If redEyeData(i, j) = PIXEL_IS_MOSTLY_RED Then rTotal = rTotal + 1
            Next i
            Next j
            
            'Ignore subregions that have 10 or less red pixels
            If rTotal > 10 Then
            
                'There are a good amount of red pixels in this subregion.  Mark it as a potential highlight.
                redEyeData(x, y) = PIXEL_IS_INTERIOR_HIGHLIGHT
                
            End If
            
        End If
        
        'DEBUG ONLY!  Paint red pixels red, so we can visualize the output of our heuristics
        If redEyeData(x, y) = PIXEL_IS_INTERIOR_HIGHLIGHT Then
            quickX = x * qvDepth
            ImageData(quickX, y) = 0
            ImageData(quickX + 1, y) = 255
            ImageData(quickX + 2, y) = 0
        End If
        
    Next x
        If Not toPreview Then
            If (y And progBarCheck) = 0 Then
                If userPressedESC() Then Exit For
                SetProgBarVal y
            End If
        End If
    Next y
    
    'With potential red-eye, eye-highlight, and non-skin regions identified, it is now time to sort the highlights
    ' into contiguous regions.  Each region will be assessed in turn, and we'll try to remove as many false-positives
    ' as we can.
    
    'A dedicated "red-eye" class helps with this step.  It's basically an optimized region detector, with some
    ' optimizations applied against this dedicated use-case.
    
    'With our work complete, point ImageData() away from the DIB and deallocate it
    CopyMemory ByVal VarPtrArray(ImageData), 0&, 4
    Erase ImageData
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    finalizeImageData toPreview, dstPic

End Sub

Private Sub cmdBar_OKClick()
    Process "Red-eye removal", , GetLocalParamString(), UNDO_LAYER
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()
    sltIntensity.Value = 2#
End Sub

Private Sub Form_Activate()
    
    'Apply translations and visual themes
    MakeFormPretty Me
    
    'Draw a preview of the effect
    UpdatePreview
    
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub fxPreview_ViewportChanged()
    UpdatePreview
End Sub

'Update the preview whenever the combination slider/text control has its value changed
Private Sub sltIntensity_Change()
    UpdatePreview
End Sub

Private Sub UpdatePreview()
    If cmdBar.previewsAllowed Then Me.ApplyRedEyeCorrection GetLocalParamString(), True, fxPreview
End Sub

Private Function GetLocalParamString() As String
    GetLocalParamString = buildParamList("testing", sltIntensity.Value)
End Function
