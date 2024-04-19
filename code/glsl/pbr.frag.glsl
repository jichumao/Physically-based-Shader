#version 330 core

uniform vec3 u_CamPos;

// PBR material attributes
uniform vec3 u_Albedo;
uniform float u_Metallic;
uniform float u_Roughness;
uniform float u_AmbientOcclusion;
// Texture maps for controlling some of the attribs above, plus normal mapping
uniform sampler2D u_AlbedoMap;
uniform sampler2D u_MetallicMap;
uniform sampler2D u_RoughnessMap;
uniform sampler2D u_AOMap;
uniform sampler2D u_NormalMap;
// If true, use the textures listed above instead of the GUI slider values
uniform bool u_UseAlbedoMap;
uniform bool u_UseMetallicMap;
uniform bool u_UseRoughnessMap;
uniform bool u_UseAOMap;
uniform bool u_UseNormalMap;

// Image-based lighting
uniform samplerCube u_DiffuseIrradianceMap;
uniform samplerCube u_GlossyIrradianceMap;
uniform sampler2D u_BRDFLookupTexture;

// Varyings
in vec3 fs_Pos;
in vec3 fs_Nor; // Surface normal
in vec3 fs_Tan; // Surface tangent
in vec3 fs_Bit; // Surface bitangent
in vec2 fs_UV;
out vec4 out_Col;

const float PI = 3.14159f;

// Set the input material attributes to texture-sampled values
// if the indicated booleans are TRUE
void handleMaterialMaps(inout vec3 albedo, inout float metallic,
                        inout float roughness, inout float ambientOcclusion,
                        inout vec3 normal) {
    if(u_UseAlbedoMap) {
        albedo = pow(texture(u_AlbedoMap, fs_UV).rgb, vec3(2.2));
    }
    if(u_UseMetallicMap) {
        metallic = texture(u_MetallicMap, fs_UV).r;
    }
    if(u_UseRoughnessMap) {
        roughness = texture(u_RoughnessMap, fs_UV).r;
    }
    if(u_UseAOMap) {
        ambientOcclusion = texture(u_AOMap, fs_UV).r;
    }
    if(u_UseNormalMap) {
        // TODO: Apply normal mapping
        vec3 tangentNormal = texture(u_NormalMap, fs_UV).rgb * 2.0 - 1.0; // Convert from [0,1] to [-1,1]
        mat3 TBN = mat3(normalize(fs_Tan), normalize(fs_Bit), normalize(fs_Nor));
        normal = normalize(TBN * tangentNormal);
    }
}

vec3 fresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness)
{
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

void main()
{
    vec3  N                = fs_Nor;
    vec3  albedo           = u_Albedo;
    float metallic         = u_Metallic;
    float roughness        = u_Roughness;
    float ambientOcclusion = u_AmbientOcclusion;

    handleMaterialMaps(albedo, metallic, roughness, ambientOcclusion, N);

    // wo aka. V
    vec3  wo = normalize(u_CamPos - fs_Pos);
    // Basic albedo - R aka. F0
    vec3 R = vec3(0.04);
    R = mix(R, albedo, metallic);

    // Diffuse term
    vec3 kS = fresnelSchlickRoughness(max(dot(N, wo), 0.0), R, roughness);
    vec3 kD = 1.0 - kS;
    vec3 irradiance = texture(u_DiffuseIrradianceMap, N).rgb;
    vec3 diffuse = irradiance * albedo;

    // Specular term
    const float maxReflectionLOD = 4.0;
    // wi aka. R
    vec3 wi = reflect(-wo, N);
    vec3 prefilteredColor = textureLod(u_GlossyIrradianceMap, wi, roughness * maxReflectionLOD).rgb;
    vec2 brdf = texture(u_BRDFLookupTexture, vec2(max(dot(N, wo), 0.0), roughness)).rg;
    vec3 specular = prefilteredColor * (kS * brdf.x + brdf.y);

    // Environment light color
    vec3 ambient = (kD * diffuse + specular) * ambientOcclusion;

    // Apply Reinhard tonemapping and gamma correction
    vec3 color = ambient / (ambient + vec3(1.0));
    color = pow(color, vec3(1.0/2.2));

    // Set the output color
    out_Col = vec4(color, 1.0);
}
