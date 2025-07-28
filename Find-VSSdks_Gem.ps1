<#
.SYNOPSIS
    Detecta con precisión qué SDKs de .NET Framework están instalados en cada instancia de Visual Studio.
.DESCRIPTION
    Este script combina dos métodos para obtener un resultado fiable:
    1. Usa la herramienta oficial 'vswhere.exe' para descubrir todas las instalaciones de Visual Studio y sus metadatos (nombre, versión, ID).
    2. Para cada instancia, lee su archivo de registro 'state.json' para verificar la lista exacta de componentes que fueron seleccionados durante su instalación.
.NOTES
    Autor: Gemini Code Assist
    Versión: 1.0 (Final)
    Dependencias: Requiere que Visual Studio o su instalador esté presente para que 'vswhere.exe' exista.
    Permisos: Se recomienda ejecutar este script como Administrador para poder acceder a la carpeta 'C:\ProgramData'.
#>

# Define una tabla hash con los SDKs que queremos buscar.
# La 'clave' es la versión legible (ej. "4.8") y el 'valor' es el ID de componente oficial que usa el instalador de Visual Studio.
$requiredSdks = @{
    "4.7.2" = "Microsoft.Net.Component.4.7.2.SDK"
    "4.8"   = "Microsoft.Net.Component.4.8.SDK"
    "4.8.1" = "Microsoft.Net.Component.4.8.1.SDK"
}

# Define la ruta estándar a la herramienta 'vswhere.exe'.
$vswherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

# Comprueba si 'vswhere.exe' existe en la ruta especificada.
if (-not (Test-Path $vswherePath)) {
    # Si no se encuentra, muestra un mensaje de error y termina la ejecución del script.
    Write-Error "Error: vswhere.exe no se encontró en '$vswherePath'. Asegúrate de que Visual Studio o su instalador esté presente en el sistema."
    exit 1
}

# Informa al usuario que la búsqueda de instancias ha comenzado.
Write-Host "Buscando instancias de Visual Studio..." -ForegroundColor Cyan

# Inicia un bloque try/catch para manejar posibles errores al ejecutar vswhere.exe.
try {
    # Ejecuta vswhere.exe para obtener todas las instancias (-all), en formato JSON (-format) y sin logo (-nologo).
    # La salida JSON se convierte en objetos de PowerShell para un manejo sencillo.
    $vsInstances = & $vswherePath -all -format json -nologo | ConvertFrom-Json -ErrorAction Stop
}
catch {
    # Si ocurre un error, lo muestra en pantalla y termina la ejecución.
    Write-Error "Error al ejecutar vswhere.exe o al analizar su salida. Error: $_"
    exit 1
}

# Comprueba si se encontraron instancias de Visual Studio.
if (-not $vsInstances) {
    # Si no se encontraron, informa al usuario y termina el script.
    Write-Host "No se encontraron instancias de Visual Studio."
    exit 0
}

# Inicia un bucle para procesar cada una de las instancias de Visual Studio encontradas.
foreach ($instance in $vsInstances) {
    # Imprime un separador y la información principal de la instancia para mayor claridad.
    Write-Host "------------------------------------------------------------"
    Write-Host "Revisando Instancia: $($instance.displayName)" -ForegroundColor White
    Write-Host "Versión: $($instance.installationVersion), Ruta: $($instance.installationPath)"
    Write-Host "------------------------------------------------------------"

    # Construye la ruta completa al archivo 'state.json', que contiene el registro de los componentes instalados para esta instancia.
    $stateJsonPath = "C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances\$($instance.instanceId)\state.json"

    # Comprueba si el archivo 'state.json' existe en la ruta.
    if (-not (Test-Path $stateJsonPath)) {
        # Si no existe, muestra una advertencia y salta a la siguiente instancia en el bucle.
        Write-Warning "No se pudo encontrar el archivo state.json para esta instancia. Omitiendo. (Ruta: $stateJsonPath)"
        Write-Warning "Asegúrate de ejecutar el script como Administrador."
        continue
    }

    # Inicia un bloque try/catch para manejar errores durante la lectura y procesamiento del archivo JSON.
    try {
        # Lee el contenido completo del archivo JSON. 
        # analice la estructura completa del JSON sin truncarla.
        $state = Get-Content -Path $stateJsonPath -Raw | ConvertFrom-Json -ErrorAction Stop

        # Inicializa un array vacío para almacenar los IDs de los paquetes.
        $installedPackageIds = @()
        
        # Comprueba si el objeto JSON contiene la propiedad 'selectedPackages'.
        if ($null -ne $state.selectedPackages) {
            # Si existe, extrae la lista de IDs de los componentes ('id') y la guarda en la variable.
            $installedPackageIds = $state.selectedPackages.id
        }

        # Inicia un bucle para cada uno de los SDKs definidos en la configuración inicial.
        foreach ($sdkVersion in $requiredSdks.Keys | Sort-Object) {
            # Obtiene el ID del componente correspondiente a la versión del SDK.
            $componentId = $requiredSdks[$sdkVersion]
            
            # Comprueba si el ID del componente actual está presente en la lista de paquetes instalados.
            # Se usa '-ccontains' para una comparación que distingue mayúsculas y minúsculas, siendo más estricta.
            if ($installedPackageIds -ccontains $componentId) {
                # Si está instalado, muestra un mensaje en color verde.
                Write-Host "[INSTALADO]   - .NET Framework SDK $sdkVersion" -ForegroundColor Green
            } else {
                # Si no está instalado, muestra un mensaje en color amarillo.
                Write-Host "[NO INSTALADO] - .NET Framework SDK $sdkVersion" -ForegroundColor Yellow
            }
        }
    }
    catch {
        # Si ocurre un error al procesar el JSON, muestra una advertencia con los detalles del error.
        Write-Warning "Falló la lectura o el análisis de '$stateJsonPath'. Error: $_"
    }
    
    # Añade una línea en blanco para separar visualmente la salida de cada instancia.
    Write-Host ""
}

# Informa al usuario que el análisis ha finalizado.
Write-Host "Análisis completado." -ForegroundColor Cyan
