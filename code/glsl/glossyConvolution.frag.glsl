#version 330 core

// Compute the irradiance within the glossy
// BRDF lobe aligned with a hard-coded wi
// that will equal our surface normal direction.
// Our surface normal direction is normalize(fs_Pos).

in vec3 fs_Pos;
out vec4 out_Col;
uniform samplerCube u_EnvironmentMap;
uniform float u_Roughness;

const float PI = 3.14159265359;

float RadicalInverse_VdC(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}
vec2 Hammersley(uint i, uint N) {
    return vec2(float(i)/float(N), RadicalInverse_VdC(i));
}

vec3 ImportanceSampleGGX(vec2 xi, vec3 N, float roughness) {
    float a = roughness * roughness;

    float phi = 2.0 * PI * xi.x;
    float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sinTheta = sqrt(1.0 - cosTheta*cosTheta);

    // from spherical coordinates to cartesian coordinates - halfway vector
    vec3 wh;
    wh.x = cos(phi) * sinTheta;
    wh.y = sin(phi) * sinTheta;
    wh.z = cosTheta;

    // from tangent-space H vector to world-space sample vector
    vec3 up        = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent   = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    vec3 whW = tangent * wh.x + bitangent * wh.y + N * wh.z;
    return normalize(whW);
}

float DistributionGGX(vec3 N, vec3 wh, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, wh), 0.0);
    float NdotH2 = NdotH * NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / denom;
}

void main() {
    // TODO
    vec3 N = normalize(fs_Pos);
    vec3 wo = N;

    const uint SAMPLE_COUNT = 1024u;
    float totalWeight = 0.0;
    vec3 Li = vec3(0.0);

    for(uint i = 0u; i < SAMPLE_COUNT; ++i) {
        vec2 xi = Hammersley(i, SAMPLE_COUNT);
        vec3 wh = ImportanceSampleGGX(xi, N, u_Roughness);
        // Reflect wo about wh
        vec3 wi  = normalize(2.0 * dot(wo, wh) * wh - wo);
        float NdotL = max(dot(N, wi), 0.0);

        if(NdotL > 0.0) {
//            Li += texture(u_EnvironmentMap, wi).rgb * NdotL;
//            totalWeight += NdotL;
            float D       = DistributionGGX(N, wh, u_Roughness);
            float nDotwh  = max(dot(N, wh), 0.0);
            float woDotwh = max(dot(wh, wo), 0.0);
            float pdf = D * nDotwh / (4.0 * woDotwh) + 0.0001;
            float resolution = 1024.0; // resolution of env map cube face
            float saTexel  = 4.0 * PI / (6.0 * resolution * resolution);
            float saSample = 1.0 / (float(SAMPLE_COUNT) * pdf + 0.0001);
            float mipLevel = u_Roughness == 0.0 ? 0.0 : 0.5 * log2(saSample / saTexel);
            Li += textureLod(u_EnvironmentMap, wi, mipLevel).rgb * NdotL;
            totalWeight += NdotL;
        }
    }

    Li = Li / totalWeight; // Gives us a weighted average of Li
    out_Col = vec4(Li, 1.0);
    //out_Col = vec4(1.0);
}
