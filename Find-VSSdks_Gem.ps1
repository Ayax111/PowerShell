<#
.SYNOPSIS
    Busca componentes específicos dentro de cada instancia de Visual Studio instalada.
.DESCRIPTION
    Esta función utiliza 'vswhere.exe' para encontrar todas las instalaciones de Visual Studio y,
    para cada una, lee su archivo de registro 'state.json' para verificar si los componentes
    especificados están instalados. La función devuelve un array de objetos, donde cada objeto
    representa un componente encontrado y la instancia de Visual Studio donde se encontró.
.NOTES
    Autor: Gemini Code Assist
    Versión: 2.0
    Dependencias: Requiere que Visual Studio o su instalador esté presente para que 'vswhere.exe' exista.
    Permisos: Se recomienda ejecutar este script como Administrador para poder acceder a la carpeta 'C:\ProgramData'.
.PARAMETER Versions
    Un array de strings que contiene las versiones numéricas de los SDKs a buscar.
.RETURN
    Un array de objetos [PSCustomObject]. Cada objeto tiene las propiedades 'Version' y 'VisualStudioInstance'.
.EXAMPLE
    $versiones = @("4.7.2", "4.8", "4.8.1")
    Find-VisualStudioComponents -Versions $versiones
#>
function Find-VisualStudioComponents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Versions
    )

    # Inicializa una lista para almacenar los resultados. Usar una lista genérica es más eficiente que el operador +=.
    $foundComponents = [System.Collections.Generic.List[psobject]]::new()

    # Define la ruta estándar a la herramienta 'vswhere.exe'.
    $vswherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

    # Comprueba si 'vswhere.exe' existe en la ruta especificada.
    if (-not (Test-Path $vswherePath)) {
        # Si no se encuentra, muestra un mensaje de error y termina la ejecución del script.
        Write-Error "Error: vswhere.exe no se encontró en '$vswherePath'. Asegúrate de que Visual Studio o su instalador esté presente en el sistema."
        return
    }

    # Inicia un bloque try/catch para manejar posibles errores al ejecutar vswhere.exe.
    try {
        # Ejecuta vswhere.exe para obtener todas las instancias (-all), en formato JSON (-format) y sin logo (-nologo).
        # La salida JSON se convierte en objetos de PowerShell para un manejo sencillo.
        $vsInstances = & $vswherePath -all -format json -nologo | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Si ocurre un error, lo muestra en pantalla y termina la ejecución.
        Write-Error "Error al ejecutar vswhere.exe o al analizar su salida. Error: $_"
        return
    }

    # Comprueba si se encontraron instancias de Visual Studio.
    if (-not $vsInstances) {
        # Si no se encontraron, escribe una advertencia y devuelve una lista vacía.
        Write-Warning "No se encontraron instancias de Visual Studio."
        return $foundComponents
    }

    # Inicia un bucle para procesar cada una de las instancias de Visual Studio encontradas.
    foreach ($instance in $vsInstances) {
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
            # Se utiliza un deserializador de .NET para máxima compatibilidad, evitando problemas con ConvertFrom-Json.
            Add-Type -AssemblyName System.Web.Extensions
            $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $serializer.RecursionLimit = 100
            $serializer.MaxJsonLength = [int]::MaxValue
            $jsonContent = Get-Content -Path $stateJsonPath -Raw
            $state = $serializer.DeserializeObject($jsonContent)

            # Inicializa un array vacío para almacenar los IDs de los paquetes.
            $installedPackageIds = @()
            
            # Comprueba si el diccionario resultante contiene la clave 'selectedPackages'.
            if ($state.ContainsKey('selectedPackages')) {
                # Si existe, itera sobre cada paquete y extrae el valor de la clave 'id'.
                $installedPackageIds = $state['selectedPackages'] | ForEach-Object { $_['id'] }
            }

            # Itera sobre cada versión solicitada para ver si está en la lista de paquetes instalados.
            foreach ($version in $Versions) {
                # Construye el ID de componente esperado para la versión actual.
                $componentId = "Microsoft.Net.Component.$version.SDK"
                
                # Comprueba si el ID del componente actual está presente en la lista de paquetes instalados.
                if ($installedPackageIds -ccontains $componentId) {
                    # Si se encuentra, crea un objeto con los detalles y lo añade a la lista de resultados.
                    $resultObject = [PSCustomObject]@{
                        Version              = $version
                        VisualStudioInstance = $instance.displayName
                    }
                    $foundComponents.Add($resultObject)
                }
            }
        }
        catch {
            # Si ocurre un error al procesar el JSON, muestra una advertencia con los detalles del error.
            Write-Warning "Falló la lectura o el análisis de '$stateJsonPath'. Error: $_"
        }
    }

    # Devuelve la lista de todos los componentes encontrados.
    return $foundComponents
}

# --- EJEMPLO DE USO ---

# 1. Definir las versiones de los SDKs a buscar en un array simple.
$versiones = @("4.7.2", "4.8", "4.8.1")

# 2. Llamar a la función y almacenar el resultado en una variable.
Write-Host "Buscando componentes SDK de .NET Framework..."
$installedSdks = Find-VisualStudioComponents -Versions $versiones

# 3. Mostrar los resultados de una manera legible.
if ($installedSdks) {
    Write-Host "Se encontraron los siguientes componentes instalados:" -ForegroundColor Green
    $installedSdks | Format-Table -AutoSize
} else {
    Write-Host "No se encontró ninguno de los SDKs especificados." -ForegroundColor Yellow
}
