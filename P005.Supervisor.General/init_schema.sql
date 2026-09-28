USE `p005.supervisor.general`;

CREATE TABLE IF NOT EXISTS `servicios` (
    `codigo` VARCHAR(50) NOT NULL PRIMARY KEY,
    `nombre` VARCHAR(150) NOT NULL,
    `proyecto` VARCHAR(50) NOT NULL,
    `tipo` VARCHAR(30) NOT NULL,
    `url_o_tarea` VARCHAR(255) NOT NULL,
    `puerto` INT NULL,
    `activo` TINYINT(1) NOT NULL DEFAULT 1,
    `estado_actual` VARCHAR(20) NOT NULL DEFAULT 'OK',
    `ultimo_check` DATETIME NULL,
    `ultimo_ok` DATETIME NULL,
    `latencia_ms` INT NOT NULL DEFAULT 0,
    `mensaje_estado` TEXT NULL,
    `vigilante_cmd` TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `incidentes` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `fecha_inicio` DATETIME NOT NULL,
    `fecha_fin` DATETIME NULL,
    `servicio_codigo` VARCHAR(50) NOT NULL,
    `tipo_evento` VARCHAR(30) NOT NULL,
    `detalle` TEXT NOT NULL,
    `asunto` VARCHAR(255) NULL,
    `destinatarios` VARCHAR(500) NULL,
    `estado_envio` VARCHAR(50) NOT NULL DEFAULT 'Enviado OK',
    `creado_el` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_servicio` (`servicio_codigo`),
    KEY `idx_fecha` (`fecha_inicio`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `historial_checks` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `fecha` DATETIME NOT NULL,
    `servicio_codigo` VARCHAR(50) NOT NULL,
    `estado` VARCHAR(20) NOT NULL,
    `latencia_ms` INT NOT NULL DEFAULT 0,
    `http_code` INT NULL,
    `mensaje` VARCHAR(255) NULL,
    KEY `idx_fecha_servicio` (`fecha`, `servicio_codigo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `configuracion` (
    `clave` VARCHAR(50) NOT NULL PRIMARY KEY,
    `valor` TEXT NOT NULL,
    `descripcion` VARCHAR(255) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
