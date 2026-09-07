@echo off
title MONITOREO Y AUTO-COMPILADOR NOVALED (PAPA E HIJOS)
color 0A
cls
echo =================================================================
echo        SISTEMA DE MONITOREO AUTONOMO EN TIEMPO REAL - NOVALED     
echo =================================================================
echo  Este proceso vigila activamente las carpetas de los hijos:
echo  1. Cotizaciones (c:\Almir_trabajos\Novaled-PestanaCotizaciones)
echo  2. Inicio (c:\Almir_trabajos\Novaled-PestanaInicio)
echo  3. Punto de Venta (c:\Almir_trabajos\Novaled-PestanaPuntoDeVenta)
echo  4. PDF y Reportes (c:\Almir_trabajos\Novaled-PDF)
echo  5. Trabajo Paralelo (c:\Almir_trabajos\Novaled-Pestana2)
echo =================================================================
echo.
powershell -ExecutionPolicy Bypass -File "C:\Almir_trabajos\Novaled Sistema\novaled_auto_compiler.ps1"
pause
