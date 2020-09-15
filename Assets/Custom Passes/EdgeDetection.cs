using UnityEngine;
using UnityEngine.Rendering.HighDefinition;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

#if UNITY_EDITOR

using UnityEditor.Rendering.HighDefinition;
using UnityEditor;

[CustomPassDrawerAttribute(typeof(EdgeDetection))]
class EdgeDetectionEditor : CustomPassDrawer
{
    private class Styles
    {
        public static float defaultLineSpace = EditorGUIUtility.singleLineHeight + EditorGUIUtility.standardVerticalSpacing;

        public static GUIContent edgeColorThreshold = new GUIContent("Edge Color Threshold", "Color Edge detect effect threshold.");
        public static GUIContent edgeNormalThreshold = new GUIContent("Normal Edge Threshold", "Normal Edge detect effect threshold.");
        public static GUIContent edgeDepthThreshold = new GUIContent("Depth Edge Threshold", "Depth Edge detect effect threshold.");
        public static GUIContent edgeRadius = new GUIContent("Edge Radius", "Radius of the edge detect effect.");
        public static GUIContent edgeColor = new GUIContent("Color", "Color of the effect");
    }

    SerializedProperty		edgeDetectColorThreshold;
    SerializedProperty      edgeDetectNormalThreshold;
    SerializedProperty      edgeDetectDepthThreshold;
    SerializedProperty		edgeRadius;
    SerializedProperty		edgeColor;

    protected override void Initialize(SerializedProperty customPass)
    {
        edgeDetectColorThreshold = customPass.FindPropertyRelative("edgeDetectColorThreshold");
        edgeDetectNormalThreshold = customPass.FindPropertyRelative("edgeDetectNormalThreshold");
        edgeDetectDepthThreshold = customPass.FindPropertyRelative("edgeDetectDepthThreshold");
        edgeRadius = customPass.FindPropertyRelative("edgeRadius");
        edgeColor = customPass.FindPropertyRelative("edgeColor");
    }

    // We only need the name to be displayed, the rest is controlled by the EdgeDetection effect
    protected override PassUIFlag commonPassUIFlags => PassUIFlag.Name;

    protected override void DoPassGUI(SerializedProperty customPass, Rect rect)
    {
        edgeDetectColorThreshold.floatValue = EditorGUI.Slider(rect, Styles.edgeColorThreshold, edgeDetectColorThreshold.floatValue, 0.1f, 5f);
        rect.y += Styles.defaultLineSpace;

        edgeDetectNormalThreshold.floatValue = EditorGUI.Slider(rect, Styles.edgeNormalThreshold, edgeDetectNormalThreshold.floatValue, 0.1f, 5f);
        rect.y += Styles.defaultLineSpace;

        edgeDetectDepthThreshold.floatValue = EditorGUI.Slider(rect, Styles.edgeDepthThreshold, edgeDetectDepthThreshold.floatValue, 0.1f, 5f);
        rect.y += Styles.defaultLineSpace;

        edgeRadius.intValue = EditorGUI.IntSlider(rect, Styles.edgeRadius, edgeRadius.intValue, 1, 6);
        rect.y += Styles.defaultLineSpace;

        edgeColor.colorValue = EditorGUI.ColorField(rect, Styles.edgeColor, edgeColor.colorValue, true, false, true);
    }

    protected override float GetPassHeight(SerializedProperty customPass) => Styles.defaultLineSpace * 6;
}

#endif

class EdgeDetection : CustomPass 
{
    public float    edgeDetectColorThreshold = 1;
    public float    edgeDetectNormalThreshold = 1;
    public float    edgeDetectDepthThreshold = 1;
    public int      edgeRadius = 1;
    public Color    edgeColor = Color.black;

    public Material edgeDetectionMeshMaterial = null;

    Material    fullscreenMaterial;
    RTHandle    edgeDetectionBuffer; // additional render target for compositing the custom and camera color buffers

    int         compositingPass;
    int         copyPass;

    // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
    // When empty this render pass will render to the active camera render target.
    // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
    // The render pipeline will ensure target setup and clearing happens in an performance manner.
    protected override void Setup(ScriptableRenderContext renderContext, CommandBuffer cmd)
    {
        fullscreenMaterial = CoreUtils.CreateEngineMaterial("FullScreen/EdgeDetection");
        edgeDetectionBuffer = RTHandles.Alloc(Vector2.one, TextureXR.slices, dimension: TextureXR.dimension, colorFormat: GraphicsFormat.R16G16B16A16_SFloat, useDynamicScale: true, name: "EdgeDetection Buffer");

        compositingPass = fullscreenMaterial.FindPass("Compositing");
        copyPass = fullscreenMaterial.FindPass("Copy");
        targetColorBuffer = TargetBuffer.Custom;
        targetDepthBuffer = TargetBuffer.Custom;
        clearFlags = ClearFlag.All;
    }

    protected override void Execute(ScriptableRenderContext renderContext, CommandBuffer cmd, HDCamera camera, CullingResults cullingResult)
    {
        if (fullscreenMaterial == null)
            return ;

        fullscreenMaterial.SetTexture("_EdgeDetectionBuffer", edgeDetectionBuffer);
        fullscreenMaterial.SetFloat("_EdgeDetectColorThreshold", edgeDetectColorThreshold);
        fullscreenMaterial.SetFloat("_EdgeDetectNormalThreshold", edgeDetectNormalThreshold);
        fullscreenMaterial.SetFloat("_EdgeDetectDepthThreshold", edgeDetectDepthThreshold);
        fullscreenMaterial.SetColor("_EdgeColor", edgeColor);
        fullscreenMaterial.SetFloat("_EdgeRadius", (float)edgeRadius);


        CoreUtils.SetRenderTarget(cmd, edgeDetectionBuffer, ClearFlag.All);
        CoreUtils.DrawFullScreen(cmd, fullscreenMaterial, shaderPassId: compositingPass);

        SetCameraRenderTarget(cmd);
        CoreUtils.DrawFullScreen(cmd, fullscreenMaterial, shaderPassId: copyPass);
    }

    protected override void Cleanup()
    {
        CoreUtils.Destroy(fullscreenMaterial);
        edgeDetectionBuffer.Release();
    }
}